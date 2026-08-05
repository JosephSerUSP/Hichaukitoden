-- Shared retro mesh shader core for 3D world and item rendering.
-- Provides GLSL source composition for vertex snapping, affine UV mapping,
-- ordered dithering, color quantization, and surface lighting.

local retro_mesh_shader = {}

local sharedShaderSource = [[
    float orderedDither(vec2 position)
    {
        vec2 cell = mod(floor(position), 4.0);
        float x = cell.x;
        float y = cell.y;
        float row0 = (x < 1.0) ? 0.0 : ((x < 2.0) ? 8.0 : ((x < 3.0) ? 2.0 : 10.0));
        float row1 = (x < 1.0) ? 12.0 : ((x < 2.0) ? 4.0 : ((x < 3.0) ? 14.0 : 6.0));
        float row2 = (x < 1.0) ? 3.0 : ((x < 2.0) ? 11.0 : ((x < 3.0) ? 1.0 : 9.0));
        float row3 = (x < 1.0) ? 15.0 : ((x < 2.0) ? 7.0 : ((x < 3.0) ? 13.0 : 5.0));
        return ((y < 1.0) ? row0 : ((y < 2.0) ? row1 : ((y < 3.0) ? row2 : row3))) / 16.0;
    }
]]

function retro_mesh_shader.sharedSource()
    return sharedShaderSource
end

function retro_mesh_shader.buildWorldShader()
    return [[
    #ifdef VERTEX
    varying vec2 worldUV;
    varying float affineScale;
    varying vec4 worldColor;
    varying float fogVisibility;
    attribute float WorldHeight;
    attribute float FogVisibility;
    attribute vec3 SurfaceLight;
    uniform vec3 cameraPosition;
    uniform vec2 cameraForward;
    uniform vec2 cameraRight;
    uniform float fovHalfX;
    uniform float fovHalfY;
    uniform float nearPlane;
    uniform float farPlane;
    uniform float baseViewportWidth;
    uniform float baseViewportHeight;
    uniform float targetWidth;
    uniform float targetHeight;
    uniform float viewportCenterY;
    uniform float affineTextures;
    uniform float vertexSnapPixels;
    uniform float fogStart;
    uniform float fogDistance;
    uniform float fogSharpness;
    uniform float fogMinFactor;
    uniform float fogBands;
    uniform vec3 playerLightColor;
    uniform float playerLightRadius;
    uniform float playerLightFalloff;

    vec4 position(mat4 transform_projection, vec4 vertex_position)
    {
        vec3 relative = vec3(VertexPosition.xy, WorldHeight) - cameraPosition;
        float depth = dot(relative.xy, cameraForward);
        float safeDepth = depth;
        worldUV = mix(VertexTexCoord.xy, VertexTexCoord.xy * safeDepth, affineTextures);
        affineScale = mix(1.0, safeDepth, affineTextures);
        vec3 dynamicLight = SurfaceLight;
        if (playerLightRadius > 0.0) {
            float playerDistance = length(relative.xy);
            if (playerDistance < playerLightRadius) {
                float strength = pow(1.0 - playerDistance / playerLightRadius, playerLightFalloff);
                dynamicLight = min(vec3(1.0), dynamicLight + playerLightColor * strength);
            }
        }
        worldColor = vec4(dynamicLight, 1.0);
        float safeFogDistance = max(fogDistance, 0.001);
        float normalizedFog = clamp((max(0.05, depth) - fogStart) / safeFogDistance, 0.0, 1.0);
        if (fogSharpness != 1.0) normalizedFog = pow(normalizedFog, fogSharpness);
        fogVisibility = 1.0 - normalizedFog * (1.0 - fogMinFactor);
        if (fogBands > 1.0) {
            fogVisibility = floor(fogVisibility * fogBands + 0.5) / fogBands;
        }
        float horizontal = dot(relative.xy, cameraRight);
        float vertical = relative.z;
        float ndcDepth = (farPlane + nearPlane) / (farPlane - nearPlane)
            - (2.0 * farPlane * nearPlane)
                / ((farPlane - nearPlane) * safeDepth);
        float viewportTop = (2.0 * viewportCenterY / targetHeight) - 1.0;
        float ndcX = horizontal / (fovHalfX * safeDepth) * (baseViewportWidth / targetWidth);
        float ndcY = viewportTop
            - vertical / (fovHalfY * safeDepth) * (baseViewportHeight / targetHeight);
        if (vertexSnapPixels > 0.0) {
            float pixelX = (ndcX + 1.0) * targetWidth * 0.5;
            float pixelY = (ndcY + 1.0) * targetHeight * 0.5;
            pixelX = floor(pixelX / vertexSnapPixels + 0.5) * vertexSnapPixels;
            pixelY = floor(pixelY / vertexSnapPixels + 0.5) * vertexSnapPixels;
            ndcX = pixelX * 2.0 / targetWidth - 1.0;
            ndcY = pixelY * 2.0 / targetHeight - 1.0;
        }
        return vec4(ndcX * safeDepth, ndcY * safeDepth, ndcDepth * safeDepth, safeDepth);
    }
    #endif

    #ifdef PIXEL
    varying vec2 worldUV;
    varying float affineScale;
    varying vec4 worldColor;
    varying float fogVisibility;
    uniform vec3 fogColor;
    uniform float ditherLevels;

]] .. sharedShaderSource .. [[

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 texel = Texel(texture, worldUV / affineScale);
        if (texel.a < 0.01) discard;
        vec3 lit = texel.rgb * color.rgb * worldColor.rgb;
        vec3 fogged = mix(fogColor, lit, fogVisibility);
        if (ditherLevels > 1.0) {
            float threshold = orderedDither(screen_coords) - 0.5;
            fogged = floor(clamp(fogged + threshold / ditherLevels, 0.0, 1.0) * ditherLevels + 0.5) / ditherLevels;
        }
        return vec4(fogged, texel.a * color.a);
    }
    #endif
]]
end

function retro_mesh_shader.buildItemShader()
    return [[
    #ifdef VERTEX
    attribute vec3 VertexNormal;

    varying vec2 worldUV;
    varying float affineScale;
    varying vec4 worldColor;

    uniform vec3 modelCenter;
    uniform float modelAngle;
    uniform float halfWidth;
    uniform float halfHeight;
    uniform float vertexSnapPixels;
    uniform float targetWidth;
    uniform float targetHeight;
    uniform vec3 lightDir;
    uniform vec3 materialColor;

    vec4 position(mat4 transform_projection, vec4 vertex_position)
    {
        vec3 pos = VertexPosition.xyz - modelCenter;
        vec3 norm = VertexNormal.xyz;

        float cosA = cos(modelAngle);
        float sinA = sin(modelAngle);

        float rotX = pos.x * cosA - pos.y * sinA;
        float rotY = pos.x * sinA + pos.y * cosA;
        float rotZ = pos.z;

        float normX = norm.x * cosA - norm.y * sinA;
        float normY = norm.x * sinA + norm.y * cosA;
        float normZ = norm.z;

        float NdotL = max(0.0, dot(vec3(normX, normY, normZ), lightDir));
        float ambient = 0.35;
        float lightIntensity = ambient + (1.0 - ambient) * NdotL;

        worldColor = vec4(VertexColor.rgb * materialColor * lightIntensity, VertexColor.a);

        float ndcX = rotX / halfWidth;
        float ndcY = -rotZ / halfHeight;

        if (vertexSnapPixels > 0.0) {
            float pixelX = (ndcX + 1.0) * targetWidth * 0.5;
            float pixelY = (ndcY + 1.0) * targetHeight * 0.5;
            pixelX = floor(pixelX / vertexSnapPixels + 0.5) * vertexSnapPixels;
            pixelY = floor(pixelY / vertexSnapPixels + 0.5) * vertexSnapPixels;
            ndcX = pixelX * 2.0 / targetWidth - 1.0;
            ndcY = pixelY * 2.0 / targetHeight - 1.0;
        }

        float depthScale = max(halfWidth, halfHeight) * 4.0;
        float ndcZ = clamp(rotY / depthScale, -0.99, 0.99);

        worldUV = VertexTexCoord.xy;
        affineScale = 1.0;

        return vec4(ndcX, ndcY, ndcZ, 1.0);
    }
    #endif

    #ifdef PIXEL
    varying vec2 worldUV;
    varying float affineScale;
    varying vec4 worldColor;

    uniform float ditherLevels;
    uniform float hasTexture;

]] .. sharedShaderSource .. [[

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 texel = vec4(1.0);
        if (hasTexture > 0.5) {
            texel = Texel(texture, worldUV / affineScale);
        }
        if (texel.a < 0.01) discard;

        vec3 lit = texel.rgb * color.rgb * worldColor.rgb;
        if (ditherLevels > 1.0) {
            float threshold = orderedDither(screen_coords) - 0.5;
            lit = floor(clamp(lit + threshold / ditherLevels, 0.0, 1.0) * ditherLevels + 0.5) / ditherLevels;
        }
        return vec4(lit, texel.a * color.a * worldColor.a);
    }
    #endif
]]
end

return retro_mesh_shader
