(function (root, factory) {
    if (typeof define === 'function' && define.amd) {
        define([], factory);
    } else if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.EventPresentation = factory();
    }
}(typeof self !== 'undefined' ? self : this, function () {
    'use strict';

    function readPresentationField(object, key) {
        if (!object) return undefined;
        return object[key];
    }

    function writePresentationField(object, key, mode, value, isCommonEvent) {
        if (!object) return;
        if (isCommonEvent) {
            if (mode === 'none' || mode === 'inherit' || value === '' || value === null || value === undefined || value === false) {
                delete object[key];
            } else {
                object[key] = value;
            }
        } else {
            if (mode === 'inherit' || mode === undefined || mode === null) {
                delete object[key];
            } else if (mode === 'suppress' || value === false) {
                object[key] = false;
            } else if (mode === 'override' || mode === 'value') {
                if (value === '' || value === null || value === undefined) {
                    delete object[key];
                } else {
                    object[key] = value;
                }
            }
        }
        return object;
    }

    function serializeEventPresentation(formState, target) {
        target = target || {};
        writePresentationField(target, 'model', formState.modelMode, formState.modelValue, false);
        writePresentationField(target, 'interactionFocus', formState.focusMode, formState.focusValue, false);
        return target;
    }

    function serializeCommonEventPresentation(formState, target) {
        target = target || {};
        writePresentationField(target, 'model', formState.modelValue ? 'value' : 'none', formState.modelValue, true);
        writePresentationField(target, 'interactionFocus', formState.focusValue ? 'value' : 'none', formState.focusValue, true);
        return target;
    }

    return {
        readPresentationField: readPresentationField,
        writePresentationField: writePresentationField,
        serializeEventPresentation: serializeEventPresentation,
        serializeCommonEventPresentation: serializeCommonEventPresentation
    };
}));
