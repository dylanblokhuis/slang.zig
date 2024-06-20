//  Severity | Facility | Code
//     ---------|----------|-----
//     31       |    30-16 | 15-0
const SlangResult = packed struct(c_int) {
    severity: u1,
    facility: u15,
    code: u16,

    pub fn hasFailed(self: SlangResult) bool {
        return self.severity < 0;
    }

    pub fn hasSucceeded(self: SlangResult) bool {
        return self.severity >= 0;
    }

    pub fn getFacility(self: SlangResult) u15 {
        return self.facility;
    }
    pub fn getCode(self: SlangResult) u16 {
        return self.code;
    }
};
const SlangUInt32 = c_uint;
const SlangInt32 = c_int;
const SlangInt = c_int;
const SlangUInt = c_uint;
const SlangSSizeT = c_int;
const SlangSizeT = c_uint;
const SlangBool = bool;
const SlangSession = opaque {};
const SlangCompileRequest = opaque {};
const SlangProfileID = c_uint;

const SlangCompileTarget = enum(c_int) {
    SLANG_TARGET_UNKNOWN,
    SLANG_TARGET_NONE,
    SLANG_GLSL,
    SLANG_GLSL_VULKAN_DEPRECATED, //< deprecated and removed: just use `SLANG_GLSL`.
    SLANG_GLSL_VULKAN_ONE_DESC_DEPRECATED, //< deprecated and removed.
    SLANG_HLSL,
    SLANG_SPIRV,
    SLANG_SPIRV_ASM,
    SLANG_DXBC,
    SLANG_DXBC_ASM,
    SLANG_DXIL,
    SLANG_DXIL_ASM,
    SLANG_C_SOURCE, //< The C language
    SLANG_CPP_SOURCE, //< C++ code for shader kernels.
    SLANG_HOST_EXECUTABLE, //< Standalone binary executable (for hosting CPU/OS)
    SLANG_SHADER_SHARED_LIBRARY, //< A shared library/Dll for shader kernels (for hosting CPU/OS)
    SLANG_SHADER_HOST_CALLABLE, //< A CPU target that makes the compiled shader code available to be run immediately
    SLANG_CUDA_SOURCE, //< Cuda source
    SLANG_PTX, //< PTX
    SLANG_CUDA_OBJECT_CODE, //< Object code that contains CUDA functions.
    SLANG_OBJECT_CODE, //< Object code that can be used for later linking
    SLANG_HOST_CPP_SOURCE, //< C++ code for host library or executable.
    SLANG_HOST_HOST_CALLABLE, //< Host callable host code (ie non kernel/shader)
    SLANG_CPP_PYTORCH_BINDING, //< C++ PyTorch binding code.
    SLANG_METAL, //< Metal shading language
    SLANG_METAL_LIB, //< Metal library
    SLANG_METAL_LIB_ASM, //< Metal library assembly
    SLANG_HOST_SHARED_LIBRARY, //< A shared library/Dll for host code (for hosting CPU/OS)
    SLANG_TARGET_COUNT_OF,
};

const SlangTargetFlags = enum(c_uint) {
    // When compiling for a D3D Shader Model 5.1 or higher target, allocate
    //   distinct register spaces for parameter blocks.
    //
    //   @deprecated This behavior is now enabled unconditionally.
    SLANG_TARGET_FLAG_PARAMETER_BLOCKS_USE_REGISTER_SPACES = 1 << 4,

    // When set, will generate target code that contains all entrypoints defined
    //   in the input source or specified via the `spAddEntryPoint` function in a
    //   single output module (library/source file).
    SLANG_TARGET_FLAG_GENERATE_WHOLE_PROGRAM = 1 << 8,

    // When set, will dump out the IR between intermediate compilation steps.
    SLANG_TARGET_FLAG_DUMP_IR = 1 << 9,

    // When set, will generate SPIRV directly rather than via glslang.
    SLANG_TARGET_FLAG_GENERATE_SPIRV_DIRECTLY = 1 << 10,
};

const ShaderCompileFlags = enum(c_uint) {
    // Do as little mangling of names as possible, to try to preserve original names
    SLANG_COMPILE_FLAG_NO_MANGLING = 1 << 3,

    // Skip code generation step, just check the code and generate layout
    SLANG_COMPILE_FLAG_NO_CODEGEN = 1 << 4,

    // Obfuscate shader names on release products
    SLANG_COMPILE_FLAG_OBFUSCATE = 1 << 5,

    // Deprecated flags: kept around to allow existing applications to
    // compile. Note that the relevant features will still be left in
    // their default state.
    SLANG_COMPILE_FLAG_NO_CHECKING = 0,
    SLANG_COMPILE_FLAG_SPLIT_MIXED_TYPES = 0,
};

const SlangSourceLanguage = enum(c_int) {
    SLANG_SOURCE_LANGUAGE_UNKNOWN,
    SLANG_SOURCE_LANGUAGE_SLANG,
    SLANG_SOURCE_LANGUAGE_HLSL,
    SLANG_SOURCE_LANGUAGE_GLSL,
    SLANG_SOURCE_LANGUAGE_C,
    SLANG_SOURCE_LANGUAGE_CPP,
    SLANG_SOURCE_LANGUAGE_CUDA,
    SLANG_SOURCE_LANGUAGE_SPIRV,
    SLANG_SOURCE_LANGUAGE_METAL,
    SLANG_SOURCE_LANGUAGE_COUNT_OF,
};

const SlangStage = enum(SlangUInt32) {
    SLANG_STAGE_NONE,
    SLANG_STAGE_VERTEX,
    SLANG_STAGE_HULL,
    SLANG_STAGE_DOMAIN,
    SLANG_STAGE_GEOMETRY,
    SLANG_STAGE_FRAGMENT,
    SLANG_STAGE_COMPUTE,
    SLANG_STAGE_RAY_GENERATION,
    SLANG_STAGE_INTERSECTION,
    SLANG_STAGE_ANY_HIT,
    SLANG_STAGE_CLOSEST_HIT,
    SLANG_STAGE_MISS,
    SLANG_STAGE_CALLABLE,
    SLANG_STAGE_MESH,
    SLANG_STAGE_AMPLIFICATION,

    // alias:
    // SLANG_STAGE_PIXEL = @intFromEnum(enum_or_tagged_union: anytype).SLANG_STAGE_FRAGMENT,
};

pub extern fn spGetBuildTagString() [*c]u8;
pub extern fn spCreateSession() *SlangSession;
pub extern fn spDestroySession(session: *SlangSession) void;

pub extern fn spCreateCompileRequest(session: *SlangSession) *SlangCompileRequest;
pub extern fn spDestroyCompileRequest(request: *SlangCompileRequest) void;

/// when it returns 0, it means the profile is not found
pub extern fn spFindProfile(session: *SlangSession, name: [*c]const u8) SlangProfileID;
pub extern fn spSetTargetProfile(request: *SlangCompileRequest, target_index: c_int, profile: SlangProfileID) void;

pub extern fn spAddCodeGenTarget(request: *SlangCompileRequest, target: SlangCompileTarget) c_int;
pub extern fn spSetCodeGenTarget(request: *SlangCompileRequest, target: SlangCompileTarget) void;
pub extern fn spSetTargetFlags(request: *SlangCompileRequest, target_index: c_int, flags: SlangTargetFlags) void;

pub extern fn spAddEntryPoint(request: *SlangCompileRequest, translation_unit_index: c_int, name: [*c]const u8, stage: SlangStage) c_int;

pub extern fn spSetCompileFlags(request: *SlangCompileRequest, flags: ShaderCompileFlags) void;
pub extern fn spGetCompileFlags(request: *SlangCompileRequest) ShaderCompileFlags;

pub extern fn spCompile(request: *SlangCompileRequest) SlangResult;
pub extern fn spAddTranslationUnit(request: *SlangCompileRequest, source_language: SlangSourceLanguage, name: [*c]const u8) c_int;
pub extern fn spAddTranslationUnitSourceFile(request: *SlangCompileRequest, translation_unit_index: c_int, path: [*c]const u8) void;
pub extern fn spAddTranslationUnitSourceString(request: *SlangCompileRequest, translation_unit_index: c_int, path: [*c]const u8, source: [*c]const u8) void;

pub extern fn spGetEntryPointCode(request: *SlangCompileRequest, entry_point_index: c_int, out_size: *usize) *anyopaque;

// spComputeStringHash
// spSetTargetProfile
// spSetDumpIntermediates
// spProcessCommandLineArguments
// spSetWriter
// spSessionCheckPassThroughSupport
// spSetGlobalGenericArgs
// spGetWriter
// spAddBuiltins
// spIsParameterLocationUsed
// spAddEntryPointEx
// spGetDiagnosticOutput
// spGetCompileTimeProfile
// spExtractRepro
// spAddEntryPoint
// spSetDumpIntermediatePrefix
// spLoadReproAsFileSystem
// spDestroySession
// spFindProfile
// spSessionSetSharedLibraryLoader
// spGetTranslationUnitSource
// spSetDebugInfoLevel
// spGetReflection
// spSetTargetForceGLSLScalarBufferLayout
// spGetContainerCode
// spSetDefaultModuleName
// spSetTypeNameForEntryPointExistentialTypeParam
// spSetDebugInfoFormat
// spSaveRepro
// spSetTargetMatrixLayoutMode
// spCompileRequest_getEntryPoint
// spGetTargetHostCallable
// spSetOutputContainerFormat
// spCompileRequest_getSession
// spGetBuildTagString
// spSetLineDirectiveMode
// spCreateSession
// spGetDiagnosticOutputBlob
// spSetTargetUseMinimumSlangOptimization
// spGetEntryPointCodeBlob
// spGetEntryPointSource
// spLoadRepro
// spSetDiagnosticFlags
// spCreateCompileRequest
// spCompile
// spAddTargetCapability
// spSetPassThrough
// spAddTranslationUnitSourceFile
// spGetDependencyFilePath
// spGetDependencyFileCount
// spSetCodeGenTarget
// spOverrideDiagnosticSeverity
// spGetTranslationUnitCount
// spAddTranslationUnitSourceString
// spSetMatrixLayoutMode
// spAddSearchPath
// spTranslationUnit_addPreprocessorDefine
// spSetFileSystem
// spSetTargetLineDirectiveMode
// spCompileRequest_getProgram
// spSetIgnoreCapabilityCheck
// spSessionGetSharedLibraryLoader
// spDestroyCompileRequest
// spGetDiagnosticFlags
// spAddTranslationUnitSourceBlob
// spAddPreprocessorDefine
// spGetEntryPointHostCallable
// spSetCompileFlags
// spAddTranslationUnit
// spEnableReproCapture
// spFindCapability
// spSetTypeNameForGlobalExistentialTypeParam
// spGetEntryPointCode
// spAddCodeGenTarget
// spAddLibraryReference
// spSetTargetFloatingPointMode
// spAddTranslationUnitSourceStringSpan
// spCompileRequest_getProgramWithEntryPoints
// spSessionCheckCompileTargetSupport
// spGetCompileRequestCode
// spSetOptimizationLevel
// spCompileRequest_getModule
// spGetCompileFlags
// spSetTargetFlags
// spSetDiagnosticCallback
// spGetTargetCodeBlob

// spReflectionTypeLayout_GetMatrixLayoutMode
// spReflectionUserAttribute_GetArgumentCount
// spReflectionTypeLayout_GetSize
// spReflectionTypeLayout_getDescriptorSetDescriptorRangeType
// spReflection_getHashedString
// spReflectionEntryPoint_getVarLayout
// spReflectionVariableLayout_getStage
// spReflectionEntryPoint_getNameOverride
// spReflectionTypeParameter_GetConstraintCount
// spReflectionTypeLayout_getSubObjectRangeSpaceOffset
// spReflectionType_GetFieldByIndex
// spReflectionEntryPoint_getComputeWaveSize
// spReflectionTypeLayout_getBindingRangeBindingCount
// spReflection_GetParameterCount
// spReflectionTypeLayout_getDescriptorSetDescriptorRangeDescriptorCount
// spReflectionEntryPoint_getName
// spReflectionType_GetResourceAccess
// spReflectionTypeLayout_GetFieldCount
// spReflection_getGlobalParamsTypeLayout
// spReflectionVariableLayout_GetSemanticName
// spReflectionTypeLayout_GetElementTypeLayout
// spReflectionTypeLayout_findFieldIndexByName
// spReflectionTypeLayout_GetElementStride
// spReflectionVariable_GetType
// spReflectionVariableLayout_GetSemanticIndex
// spReflectionTypeLayout_getBindingRangeLeafVariable
// spReflectionTypeLayout_GetCategoryCount
// spReflectionTypeParameter_GetName
// spReflectionType_getSpecializedTypeArgType
// spReflectionType_GetName
// spReflectionTypeLayout_getSubObjectRangeOffset
// spReflectionTypeLayout_getBindingRangeType
// spReflectionTypeLayout_getSubObjectRangeBindingRangeIndex
// spReflectionVariable_FindModifier
// spReflectionEntryPoint_hasDefaultConstantBuffer
// spReflection_getGlobalConstantBufferSize
// spReflectionType_GetScalarType
// spReflectionVariableLayout_GetVariable
// spReflectionTypeLayout_GetParameterCategory
// spReflectionParameter_GetBindingIndex
// spReflectionTypeLayout_getDescriptorSetDescriptorRangeIndexOffset
// spReflection_getEntryPointCount
// spReflectionTypeLayout_getKind
// spReflectionVariableLayout_GetOffset
// spReflectionEntryPoint_getStage
// spReflectionType_GetUserAttribute
// spReflectionTypeLayout_getBindingRangeDescriptorSetIndex
// spReflectionVariableLayout_GetTypeLayout
// spReflection_FindTypeByName
// spReflectionTypeLayout_getBindingRangeCount
// spReflectionUserAttribute_GetArgumentValueInt
// spReflectionTypeLayout_getExplicitCounterBindingRangeOffset
// spReflectionType_GetElementCount
// spReflectionTypeLayout_getDescriptorSetSpaceOffset
// spReflectionEntryPoint_getParameterCount
// spReflectionTypeLayout_getBindingRangeDescriptorRangeCount
// spReflectionTypeLayout_getContainerVarLayout
// spReflectionType_GetKind
// spReflectionType_GetUserAttributeCount
// spReflectionTypeParameter_GetConstraintByIndex
// spReflectionTypeLayout_GetStride
// spReflectionTypeLayout_getDescriptorSetDescriptorRangeCategory
// spReflection_getHashedStringCount
// spReflectionTypeLayout_GetCategoryByIndex
// spReflectionVariable_GetName
// spReflectionVariableLayout_GetSpace
// spReflectionTypeLayout_getSubObjectRangeCount
// spReflectionUserAttribute_GetArgumentValueFloat
// spReflectionType_GetElementType
// spReflectionUserAttribute_GetArgumentType
// spReflectionTypeLayout_getGenericParamIndex
// spReflectionTypeLayout_getAlignment
// spReflectionTypeLayout_getBindingRangeFirstDescriptorRangeIndex
// spReflectionUserAttribute_GetName
// spReflectionType_GetResourceResultType
// spReflection_getGlobalParamsVarLayout
// spReflectionTypeLayout_GetType
// spReflectionTypeLayout_getSpecializedTypePendingDataVarLayout
// spReflectionTypeLayout_GetElementVarLayout
// spReflectionEntryPoint_getParameterByIndex
// spReflectionTypeLayout_getPendingDataTypeLayout
// spReflectionType_FindUserAttributeByName
// spReflection_findEntryPointByName
// spReflectionEntryPoint_getComputeThreadGroupSize
// spReflection_GetTypeParameterCount
// spReflectionTypeLayout_GetFieldByIndex
// spReflectionTypeLayout_getBindingRangeLeafTypeLayout
// spReflectionTypeLayout_getDescriptorSetDescriptorRangeCount
// spReflection_getGlobalConstantBufferBinding
// spReflection_getEntryPointByIndex
// spReflectionType_GetFieldCount
// spReflectionTypeLayout_getDescriptorSetCount
// spReflection_GetParameterByIndex
// spReflectionType_getSpecializedTypeArgCount
// spReflectionTypeParameter_GetIndex
// spReflectionType_GetColumnCount
// spReflectionVariableLayout_getPendingDataLayout
// spReflectionTypeLayout_getFieldBindingRangeOffset
// spReflectionType_GetRowCount
// spReflectionParameter_GetBindingSpace
// spReflectionEntryPoint_usesAnySampleRateInput
// spReflectionEntryPoint_getResultVarLayout
// spReflection_specializeType
// spReflection_GetTypeParameterByIndex
// spReflectionType_GetResourceShape
// spReflectionUserAttribute_GetArgumentValueString
// spReflectionVariable_GetUserAttribute
// spReflectionTypeLayout_GetExplicitCounter
// spReflectionTypeLayout_isBindingRangeSpecializable
// spReflectionVariable_FindUserAttributeByName
// spReflection_GetTypeLayout
// spReflection_FindTypeParameter
// spReflectionVariable_GetUserAttributeCount
