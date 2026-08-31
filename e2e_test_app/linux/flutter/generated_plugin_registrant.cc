//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <sora_sdk/sora_sdk_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) sora_sdk_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "SoraSdkPlugin");
  sora_sdk_plugin_register_with_registrar(sora_sdk_registrar);
}
