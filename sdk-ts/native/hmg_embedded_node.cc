#include <node_api.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

using MemoryLocalFn = void *(*)(const char *, const char *);
using MemoryTemporaryFn = void *(*)(const char *);
using MemoryAddFn = char *(*)(void *, const char *, const char *);
using MemorySearchFn = char *(*)(void *, const char *, const char *, size_t);
using MemoryFreeFn = void (*)(void *);
using LastErrorFn = char *(*)();
using StringFreeFn = void (*)(char *);

struct HmgApi {
  void *library = nullptr;
  MemoryLocalFn local = nullptr;
  MemoryTemporaryFn temporary = nullptr;
  MemoryAddFn add = nullptr;
  MemorySearchFn search = nullptr;
  MemoryFreeFn free_memory = nullptr;
  LastErrorFn last_error = nullptr;
  StringFreeFn string_free = nullptr;
};

struct MemoryHandle {
  void *ptr = nullptr;
};

HmgApi g_api;

void Throw(napi_env env, const char *message) { napi_throw_error(env, nullptr, message); }

std::string DynamicLibraryError() {
#ifdef _WIN32
  DWORD error = GetLastError();
  if (error == 0) {
    return "unknown Windows dynamic library error";
  }
  LPSTR buffer = nullptr;
  DWORD size = FormatMessageA(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<LPSTR>(&buffer), 0, nullptr);
  std::string message = size > 0 && buffer != nullptr ? std::string(buffer, size)
                                                     : "Windows dynamic library error";
  if (buffer != nullptr) {
    LocalFree(buffer);
  }
  return message;
#else
  const char *message = dlerror();
  return message == nullptr ? "unknown POSIX dynamic library error" : std::string(message);
#endif
}

void *OpenDynamicLibrary(const std::string &library_path) {
#ifdef _WIN32
  return reinterpret_cast<void *>(LoadLibraryA(library_path.c_str()));
#else
  return dlopen(library_path.c_str(), RTLD_NOW | RTLD_LOCAL);
#endif
}

void *LookupSymbol(void *library, const char *name) {
#ifdef _WIN32
  return reinterpret_cast<void *>(
      GetProcAddress(reinterpret_cast<HMODULE>(library), name));
#else
  return dlsym(library, name);
#endif
}

std::string StringArg(napi_env env, napi_value value) {
  size_t len = 0;
  napi_get_value_string_utf8(env, value, nullptr, 0, &len);
  std::vector<char> buffer(len + 1, '\0');
  napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &len);
  return std::string(buffer.data(), len);
}

std::string OptionalStringArg(napi_env env, napi_value value) {
  napi_valuetype type;
  napi_typeof(env, value, &type);
  if (type == napi_undefined || type == napi_null) {
    return "";
  }
  return StringArg(env, value);
}

std::string TakeCString(char *value) {
  if (value == nullptr) {
    return "";
  }
  std::string out(value);
  if (g_api.string_free != nullptr) {
    g_api.string_free(value);
  }
  return out;
}

std::string LastError() {
  if (g_api.last_error == nullptr) {
    return "embedded HMG native library is not loaded";
  }
  return TakeCString(g_api.last_error());
}

void *Symbol(napi_env env, const char *name) {
  void *symbol = LookupSymbol(g_api.library, name);
  if (symbol == nullptr) {
    std::string message = "missing HMG embedded symbol: ";
    message += name;
    Throw(env, message.c_str());
  }
  return symbol;
}

bool EnsureApi(napi_env env, const std::string &library_path) {
  if (g_api.library != nullptr) {
    return true;
  }
  if (library_path.empty()) {
    Throw(env, "HMG embedded library path is empty");
    return false;
  }
  g_api.library = OpenDynamicLibrary(library_path);
  if (g_api.library == nullptr) {
    std::string message = "failed to load HMG embedded library: ";
    message += DynamicLibraryError();
    Throw(env, message.c_str());
    return false;
  }
  g_api.local = reinterpret_cast<MemoryLocalFn>(Symbol(env, "hmg_embedded_memory_local"));
  g_api.temporary =
      reinterpret_cast<MemoryTemporaryFn>(Symbol(env, "hmg_embedded_memory_temporary"));
  g_api.add = reinterpret_cast<MemoryAddFn>(Symbol(env, "hmg_embedded_memory_add"));
  g_api.search = reinterpret_cast<MemorySearchFn>(Symbol(env, "hmg_embedded_memory_search"));
  g_api.free_memory = reinterpret_cast<MemoryFreeFn>(Symbol(env, "hmg_embedded_memory_free"));
  g_api.last_error = reinterpret_cast<LastErrorFn>(Symbol(env, "hmg_embedded_last_error"));
  g_api.string_free = reinterpret_cast<StringFreeFn>(Symbol(env, "hmg_embedded_string_free"));
  bool pending = false;
  napi_is_exception_pending(env, &pending);
  return !pending;
}

void FinalizeMemory(napi_env, void *data, void *) {
  auto *handle = static_cast<MemoryHandle *>(data);
  if (handle != nullptr) {
    if (handle->ptr != nullptr && g_api.free_memory != nullptr) {
      g_api.free_memory(handle->ptr);
      handle->ptr = nullptr;
    }
    delete handle;
  }
}

MemoryHandle *UnwrapHandle(napi_env env, napi_value value) {
  void *data = nullptr;
  napi_status status = napi_get_value_external(env, value, &data);
  if (status != napi_ok || data == nullptr) {
    Throw(env, "invalid embedded HMG memory handle");
    return nullptr;
  }
  auto *handle = static_cast<MemoryHandle *>(data);
  if (handle->ptr == nullptr) {
    Throw(env, "embedded HMG memory is closed");
    return nullptr;
  }
  return handle;
}

napi_value ExternalHandle(napi_env env, void *ptr) {
  auto *handle = new MemoryHandle();
  handle->ptr = ptr;
  napi_value external;
  napi_create_external(env, handle, FinalizeMemory, nullptr, &external);
  return external;
}

napi_value StringValue(napi_env env, const std::string &value) {
  napi_value out;
  napi_create_string_utf8(env, value.c_str(), value.size(), &out);
  return out;
}

napi_value Local(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    Throw(env, "local(path, userId, libraryPath) requires three arguments");
    return nullptr;
  }
  const std::string path = StringArg(env, args[0]);
  const std::string user_id = OptionalStringArg(env, args[1]);
  const std::string library_path = StringArg(env, args[2]);
  if (!EnsureApi(env, library_path)) {
    return nullptr;
  }
  void *ptr = g_api.local(path.c_str(), user_id.empty() ? nullptr : user_id.c_str());
  if (ptr == nullptr) {
    Throw(env, LastError().c_str());
    return nullptr;
  }
  return ExternalHandle(env, ptr);
}

napi_value Temporary(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 2) {
    Throw(env, "temporary(userId, libraryPath) requires two arguments");
    return nullptr;
  }
  const std::string user_id = OptionalStringArg(env, args[0]);
  const std::string library_path = StringArg(env, args[1]);
  if (!EnsureApi(env, library_path)) {
    return nullptr;
  }
  void *ptr = g_api.temporary(user_id.empty() ? nullptr : user_id.c_str());
  if (ptr == nullptr) {
    Throw(env, LastError().c_str());
    return nullptr;
  }
  return ExternalHandle(env, ptr);
}

napi_value Add(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    Throw(env, "add(handle, content, userId) requires three arguments");
    return nullptr;
  }
  MemoryHandle *handle = UnwrapHandle(env, args[0]);
  if (handle == nullptr) {
    return nullptr;
  }
  const std::string content = StringArg(env, args[1]);
  const std::string user_id = OptionalStringArg(env, args[2]);
  char *json = g_api.add(handle->ptr, content.c_str(), user_id.empty() ? nullptr : user_id.c_str());
  return StringValue(env, TakeCString(json));
}

napi_value Search(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 4) {
    Throw(env, "search(handle, query, userId, limit) requires four arguments");
    return nullptr;
  }
  MemoryHandle *handle = UnwrapHandle(env, args[0]);
  if (handle == nullptr) {
    return nullptr;
  }
  const std::string query = StringArg(env, args[1]);
  const std::string user_id = OptionalStringArg(env, args[2]);
  uint32_t limit = 10;
  napi_get_value_uint32(env, args[3], &limit);
  char *json =
      g_api.search(handle->ptr, query.c_str(), user_id.empty() ? nullptr : user_id.c_str(), limit);
  return StringValue(env, TakeCString(json));
}

napi_value Close(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 1) {
    Throw(env, "close(handle) requires one argument");
    return nullptr;
  }
  void *data = nullptr;
  napi_get_value_external(env, args[0], &data);
  auto *handle = static_cast<MemoryHandle *>(data);
  if (handle != nullptr && handle->ptr != nullptr) {
    g_api.free_memory(handle->ptr);
    handle->ptr = nullptr;
  }
  napi_value out;
  napi_get_undefined(env, &out);
  return out;
}

void Export(napi_env env, napi_value exports, const char *name, napi_callback callback) {
  napi_value fn;
  napi_create_function(env, name, NAPI_AUTO_LENGTH, callback, nullptr, &fn);
  napi_set_named_property(env, exports, name, fn);
}

napi_value Init(napi_env env, napi_value exports) {
  Export(env, exports, "local", Local);
  Export(env, exports, "temporary", Temporary);
  Export(env, exports, "add", Add);
  Export(env, exports, "search", Search);
  Export(env, exports, "close", Close);
  return exports;
}

}  // namespace

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
