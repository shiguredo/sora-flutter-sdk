#include "include/sora_sdk/sora_sdk_plugin.h"

#include <flutter_linux/flutter_linux.h>

struct _SoraSdkPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(SoraSdkPlugin, sora_sdk_plugin, g_object_get_type())

static void sora_sdk_plugin_handle_method_call(SoraSdkPlugin* self,
                                               FlMethodCall* method_call) {
  fl_method_call_respond_error(method_call, "unimplemented",
                               "Linux implementation is not wired yet.",
                               nullptr, nullptr);
}

static void sora_sdk_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(sora_sdk_plugin_parent_class)->dispose(object);
}

static void sora_sdk_plugin_class_init(SoraSdkPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = sora_sdk_plugin_dispose;
}

static void sora_sdk_plugin_init(SoraSdkPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  SoraSdkPlugin* plugin = SORA_SDK_PLUGIN(user_data);
  sora_sdk_plugin_handle_method_call(plugin, method_call);
}

void sora_sdk_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  SoraSdkPlugin* plugin =
      SORA_SDK_PLUGIN(g_object_new(sora_sdk_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "sora_sdk/method", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
