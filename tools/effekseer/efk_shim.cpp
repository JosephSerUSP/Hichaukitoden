// extern "C" shim over the Effekseer C++ runtime, so LuaJIT FFI can drive it.
//
// WHY THIS EXISTS: Effekseer exposes no C API (verified: zero `extern "C"` in
// Dev/Cpp/Effekseer or Dev/Cpp/EffekseerRendererGL). Its API is delivered
// through RefPtr smart pointers and pure-virtual interfaces, which the C ABI
// cannot express. This file keeps every RefPtr, vtable and template sealed on
// the C++ side and exposes only ints and floats -- the same approach
// EffekseerForUnity takes for P/Invoke.
//
// Effects and playback handles are addressed by plain int ids so the Lua side
// never holds a pointer.

#include <Effekseer.h>
#include <EffekseerRendererGL.h>

#include <string>
#include <vector>
#include <cstring>

#if defined(_WIN32)
#include <windows.h>
#endif
#include <GL/gl.h>

#define EFK_API extern "C" __declspec(dllexport)

namespace
{

Effekseer::ManagerRef g_manager;
EffekseerRendererGL::RendererRef g_renderer;
std::vector<Effekseer::EffectRef> g_effects;
std::string g_lastError;
float g_time = 0.0f;

// Effekseer takes UTF-16 paths. Minimal UTF-8 -> UTF-16 conversion covering
// the BMP plus surrogate pairs; asset paths here are ASCII in practice, but
// silently mangling a non-ASCII path would be the kind of quiet failure the
// project's "fail loud" rule exists to prevent.
std::u16string toU16(const char* utf8)
{
    std::u16string out;
    const unsigned char* p = reinterpret_cast<const unsigned char*>(utf8);
    while (*p)
    {
        unsigned int cp = 0;
        if (*p < 0x80) { cp = *p++; }
        else if ((*p >> 5) == 0x6) { cp = (*p & 0x1F) << 6; ++p; cp |= (*p++ & 0x3F); }
        else if ((*p >> 4) == 0xE)
        {
            cp = (*p & 0x0F) << 12; ++p;
            cp |= (*p & 0x3F) << 6; ++p;
            cp |= (*p++ & 0x3F);
        }
        else
        {
            cp = (*p & 0x07) << 18; ++p;
            cp |= (*p & 0x3F) << 12; ++p;
            cp |= (*p & 0x3F) << 6; ++p;
            cp |= (*p++ & 0x3F);
        }

        if (cp >= 0x10000)
        {
            cp -= 0x10000;
            out.push_back(static_cast<char16_t>(0xD800 + (cp >> 10)));
            out.push_back(static_cast<char16_t>(0xDC00 + (cp & 0x3FF)));
        }
        else
        {
            out.push_back(static_cast<char16_t>(cp));
        }
    }
    return out;
}

void toMatrix(const float* src, Effekseer::Matrix44& dst)
{
    for (int r = 0; r < 4; r++)
        for (int c = 0; c < 4; c++)
            dst.Values[r][c] = src[r * 4 + c];
}

// ---------------------------------------------------------------------------
// GL state guard.
//
// EffekseerRendererGL issues its own glUseProgram / glBindBuffer / VAO calls.
// LOVE caches GL state and assumes nothing else touches it, so returning from
// a draw with the state Effekseer left behind corrupts everything LOVE renders
// afterwards. Save what Effekseer is known to clobber, restore it on the way
// out. glGetIntegerv is GL 1.1 (in opengl32), but the setters are GL 2.0+ and
// must be resolved at runtime.
// ---------------------------------------------------------------------------

#define GL_ARRAY_BUFFER_BINDING_          0x8894
#define GL_ELEMENT_ARRAY_BUFFER_BINDING_  0x8895
#define GL_CURRENT_PROGRAM_               0x8B8D
#define GL_VERTEX_ARRAY_BINDING_          0x85B5
#define GL_ACTIVE_TEXTURE_                0x84E0
#define GL_TEXTURE0_                      0x84C0
#define GL_ARRAY_BUFFER_                  0x8892
#define GL_ELEMENT_ARRAY_BUFFER_          0x8893

typedef void (APIENTRY* PFN_glUseProgram)(GLuint);
typedef void (APIENTRY* PFN_glBindBuffer)(GLenum, GLuint);
typedef void (APIENTRY* PFN_glBindVertexArray)(GLuint);
typedef void (APIENTRY* PFN_glActiveTexture)(GLenum);

PFN_glUseProgram      p_glUseProgram = nullptr;
PFN_glBindBuffer      p_glBindBuffer = nullptr;
PFN_glBindVertexArray p_glBindVertexArray = nullptr;
PFN_glActiveTexture   p_glActiveTexture = nullptr;

void* glProc(const char* name)
{
#if defined(_WIN32)
    void* p = (void*)wglGetProcAddress(name);
    if (p == nullptr || p == (void*)0x1 || p == (void*)0x2 ||
        p == (void*)0x3 || p == (void*)-1)
    {
        HMODULE m = GetModuleHandleA("opengl32.dll");
        p = m ? (void*)GetProcAddress(m, name) : nullptr;
    }
    return p;
#else
    (void)name;
    return nullptr;
#endif
}

void loadGLProcs()
{
    p_glUseProgram      = (PFN_glUseProgram)glProc("glUseProgram");
    p_glBindBuffer      = (PFN_glBindBuffer)glProc("glBindBuffer");
    p_glBindVertexArray = (PFN_glBindVertexArray)glProc("glBindVertexArray");
    p_glActiveTexture   = (PFN_glActiveTexture)glProc("glActiveTexture");
}

struct GLStateGuard
{
    GLint program = 0, vao = 0, arrayBuf = 0, elemBuf = 0;
    GLint activeTex = GL_TEXTURE0_, texture2D = 0;
    GLboolean blend = GL_FALSE, depthTest = GL_FALSE, cullFace = GL_FALSE;
    GLboolean depthMask = GL_TRUE;

    GLStateGuard()
    {
        glGetIntegerv(GL_CURRENT_PROGRAM_, &program);
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING_, &vao);
        glGetIntegerv(GL_ARRAY_BUFFER_BINDING_, &arrayBuf);
        glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING_, &elemBuf);
        glGetIntegerv(GL_ACTIVE_TEXTURE_, &activeTex);
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture2D);
        blend     = glIsEnabled(GL_BLEND);
        depthTest = glIsEnabled(GL_DEPTH_TEST);
        cullFace  = glIsEnabled(GL_CULL_FACE);
        glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMask);
    }

    ~GLStateGuard()
    {
        if (p_glUseProgram)      p_glUseProgram((GLuint)program);
        if (p_glBindVertexArray) p_glBindVertexArray((GLuint)vao);
        if (p_glBindBuffer)
        {
            p_glBindBuffer(GL_ARRAY_BUFFER_, (GLuint)arrayBuf);
            p_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER_, (GLuint)elemBuf);
        }
        if (p_glActiveTexture) p_glActiveTexture((GLenum)activeTex);
        glBindTexture(GL_TEXTURE_2D, (GLuint)texture2D);

        if (blend)     glEnable(GL_BLEND);     else glDisable(GL_BLEND);
        if (depthTest) glEnable(GL_DEPTH_TEST); else glDisable(GL_DEPTH_TEST);
        if (cullFace)  glEnable(GL_CULL_FACE);  else glDisable(GL_CULL_FACE);
        glDepthMask(depthMask);
    }
};

} // namespace

EFK_API int efk_init(int instanceMax, int squareMaxCount)
{
    g_lastError.clear();
    if (g_manager) return 1; // already initialised

    loadGLProcs();

    auto device = EffekseerRendererGL::CreateGraphicsDevice(
        EffekseerRendererGL::OpenGLDeviceType::OpenGL3);
    if (device == nullptr) { g_lastError = "CreateGraphicsDevice failed"; return 0; }

    g_renderer = EffekseerRendererGL::Renderer::Create(device, squareMaxCount);
    if (g_renderer == nullptr) { g_lastError = "Renderer::Create failed"; return 0; }

    g_manager = Effekseer::Manager::Create(instanceMax);
    if (g_manager == nullptr) { g_lastError = "Manager::Create failed"; return 0; }

    g_manager->SetSpriteRenderer(g_renderer->CreateSpriteRenderer());
    g_manager->SetRibbonRenderer(g_renderer->CreateRibbonRenderer());
    g_manager->SetRingRenderer(g_renderer->CreateRingRenderer());
    g_manager->SetTrackRenderer(g_renderer->CreateTrackRenderer());
    g_manager->SetModelRenderer(g_renderer->CreateModelRenderer());

    g_manager->SetTextureLoader(g_renderer->CreateTextureLoader());
    g_manager->SetModelLoader(g_renderer->CreateModelLoader());
    g_manager->SetMaterialLoader(g_renderer->CreateMaterialLoader());
    g_manager->SetCurveLoader(Effekseer::MakeRefPtr<Effekseer::CurveLoader>());

    g_time = 0.0f;
    return 1;
}

EFK_API void efk_shutdown(void)
{
    g_effects.clear();
    g_manager.Reset();
    g_renderer.Reset();
}

// `magnification` scales the effect at load time. It is NOT cosmetic here:
// effects are authored in world units, so under the screen-space orthographic
// camera a battle scene uses (1 unit = 1 pixel at 256x240) an effect authored
// for a 3D scene renders about 20px across and reads as a speck. Either author
// effects at game scale or pass a magnification; this exposes the choice
// instead of silently hardcoding 1.0.
EFK_API int efk_load_effect(const char* utf8Path, float magnification)
{
    g_lastError.clear();
    if (!g_manager) { g_lastError = "not initialised"; return -1; }
    if (magnification <= 0.0f) magnification = 1.0f;

    std::u16string path = toU16(utf8Path);
    auto effect = Effekseer::Effect::Create(g_manager, path.c_str(), magnification);
    if (effect == nullptr)
    {
        g_lastError = std::string("Effect::Create failed for ") + utf8Path;
        return -1;
    }

    for (size_t i = 0; i < g_effects.size(); i++)
    {
        if (g_effects[i] == nullptr) { g_effects[i] = effect; return (int)i; }
    }
    g_effects.push_back(effect);
    return (int)g_effects.size() - 1;
}

EFK_API void efk_release_effect(int effectId)
{
    if (effectId < 0 || effectId >= (int)g_effects.size()) return;
    g_effects[effectId] = nullptr;
}

EFK_API int efk_play(int effectId, float x, float y, float z)
{
    if (!g_manager) return -1;
    if (effectId < 0 || effectId >= (int)g_effects.size()) return -1;
    if (g_effects[effectId] == nullptr) return -1;
    return (int)g_manager->Play(g_effects[effectId], x, y, z);
}

EFK_API void efk_stop(int handle)
{
    if (g_manager) g_manager->StopEffect((Effekseer::Handle)handle);
}

EFK_API void efk_stop_all(void)
{
    if (g_manager) g_manager->StopAllEffects();
}

EFK_API int efk_exists(int handle)
{
    if (!g_manager) return 0;
    return g_manager->Exists((Effekseer::Handle)handle) ? 1 : 0;
}

EFK_API void efk_set_location(int handle, float x, float y, float z)
{
    if (g_manager)
        g_manager->SetLocation((Effekseer::Handle)handle, Effekseer::Vector3D(x, y, z));
}

// Scale is applied about the effect's OWN origin, which is what makes it the
// right tool for the Y-axis mismatch: Effekseer authors with +Y up, a 2D canvas
// has +Y down, so an effect plays upside down. Mirroring via scale (1,-1,1)
// flips the effect's geometry in place, leaving its world position -- already
// verified correct -- untouched. Doing this in the projection instead would
// move the effect as well as flip it.
EFK_API void efk_set_scale(int handle, float x, float y, float z)
{
    if (g_manager)
        g_manager->SetScale((Effekseer::Handle)handle, x, y, z);
}

// Mirror only the rendered effect about its root-local axes. Unlike
// SetScale(), SetEffectFlip() does not modify the simulation transform, so
// billboard orientation, particle directions, and per-particle rotation are
// computed from the authored effect exactly as they were in Effekseer.
EFK_API void efk_set_effect_flip(int handle, int flipX, int flipY, int flipZ)
{
    if (!g_manager) return;

    Effekseer::EffectFlipParameter flip;
    flip.FlipX = flipX != 0;
    flip.FlipY = flipY != 0;
    flip.FlipZ = flipZ != 0;
    g_manager->SetEffectFlip((Effekseer::Handle)handle, flip);
}

EFK_API int efk_instance_count(void)
{
    return g_manager ? g_manager->GetTotalInstanceCount() : 0;
}

// deltaFrame is in Effekseer FRAMES (60fps units), not seconds. The Lua caller
// converts, so the harness clock can drive this deterministically rather than
// Effekseer reading a wall clock of its own.
EFK_API void efk_update(float deltaFrame)
{
    if (!g_manager) return;
    Effekseer::Manager::UpdateParameter param;
    param.DeltaFrame = deltaFrame;
    g_manager->Update(param);
    g_time += deltaFrame / 60.0f;
}

EFK_API void efk_set_time(float seconds)
{
    g_time = seconds;
}

EFK_API void efk_draw(const float* view16, const float* proj16)
{
    if (!g_manager || !g_renderer) return;

    GLStateGuard guard;

    // This integration renders screen-space effects after LOVE has finished
    // the 3D viewport. The canvas depth attachment still contains the world
    // geometry at that point; leaving it intact makes effects over enemies
    // fail their authored depth test while the same effects over depth-free UI
    // pixels remain visible. Effekseer owns depth relationships within this
    // overlay pass, but it must not inherit depth from the earlier world pass.
    glClear(GL_DEPTH_BUFFER_BIT);

    Effekseer::Matrix44 view, proj;
    toMatrix(view16, view);
    toMatrix(proj16, proj);

    g_renderer->SetTime(g_time);
    g_renderer->SetCameraMatrix(view);
    g_renderer->SetProjectionMatrix(proj);

    g_renderer->BeginRendering();
    Effekseer::Manager::DrawParameter drawParameter;
    drawParameter.ZNear = 0.0f;
    drawParameter.ZFar = 1.0f;
    drawParameter.ViewProjectionMatrix = g_renderer->GetCameraProjectionMatrix();
    g_manager->Draw(drawParameter);
    g_renderer->EndRendering();
}

EFK_API const char* efk_last_error(void)
{
    return g_lastError.c_str();
}
