#ifndef FLUTTER_PLUGIN_SORA_SDK_PLUGIN_H_
#define FLUTTER_PLUGIN_SORA_SDK_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

G_DECLARE_FINAL_TYPE(SoraSdkPlugin, sora_sdk_plugin, SORA, SDK_PLUGIN, GObject)

void sora_sdk_plugin_register_with_registrar(FlPluginRegistrar* registrar);

G_END_DECLS

#endif
