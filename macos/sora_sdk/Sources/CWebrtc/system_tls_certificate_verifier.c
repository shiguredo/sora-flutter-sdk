#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <limits.h>
#include <stdio.h>

#include "CWebrtc/CWebrtc.h"

/*
 * libwebrtc から渡された証明書チェーンを Apple の Security framework で
 * 検証する。
 *
 * ホスト名検証は libwebrtc 側で別途実行されるため、この callback は
 * 証明書チェーンの信頼性だけを同期的に返す。
 */
static int sora_apple_verify_tls_certificate_chain(
    const struct webrtc_SSLCertChain* chain,
    void* user_data) {
  (void)user_data;

  if (chain == NULL) {
    fprintf(stderr, "TLS certificate chain is null\n");
    return 0;
  }

  int chain_size = webrtc_SSLCertChain_GetSize(chain);
  if (chain_size <= 0) {
    fprintf(stderr, "TLS certificate chain is empty\n");
    return 0;
  }

  CFMutableArrayRef certificates = CFArrayCreateMutable(
      kCFAllocatorDefault, chain_size, &kCFTypeArrayCallBacks);
  if (certificates == NULL) {
    fprintf(stderr, "Failed to allocate TLS certificate chain\n");
    return 0;
  }

  int valid = 0;
  SecPolicyRef policy = NULL;
  SecTrustRef trust = NULL;
  CFErrorRef trust_error = NULL;

  for (int i = 0; i < chain_size; i++) {
    const struct webrtc_SSLCertificate* certificate =
        webrtc_SSLCertChain_Get(chain, i);
    if (certificate == NULL) {
      fprintf(stderr, "TLS certificate chain contains a null certificate\n");
      goto cleanup;
    }

    struct std_string_unique* der_unique =
        webrtc_SSLCertificate_ToDER(certificate);
    if (der_unique == NULL) {
      fprintf(stderr, "Failed to encode TLS certificate\n");
      goto cleanup;
    }

    struct std_string* der = std_string_unique_get(der_unique);
    size_t der_size = der == NULL ? 0 : std_string_size(der);
    const char* der_data = der == NULL ? NULL : std_string_c_str(der);
    if (der_data == NULL || der_size == 0 || der_size > LONG_MAX) {
      fprintf(stderr, "TLS certificate DER is invalid\n");
      std_string_unique_delete(der_unique);
      goto cleanup;
    }

    CFDataRef der_cf = CFDataCreate(kCFAllocatorDefault, (const UInt8*)der_data,
                                    (CFIndex)der_size);
    std_string_unique_delete(der_unique);
    if (der_cf == NULL) {
      fprintf(stderr, "Failed to allocate TLS certificate DER\n");
      goto cleanup;
    }

    SecCertificateRef certificate_ref =
        SecCertificateCreateWithData(kCFAllocatorDefault, der_cf);
    CFRelease(der_cf);
    if (certificate_ref == NULL) {
      fprintf(stderr, "Failed to parse TLS certificate\n");
      goto cleanup;
    }

    CFArrayAppendValue(certificates, certificate_ref);
    CFRelease(certificate_ref);
  }

  // サーバー証明書としての用途を検証し、ホスト名検証は libwebrtc に委ねる。
  policy = SecPolicyCreateSSL(1, NULL);
  if (policy == NULL) {
    fprintf(stderr, "Failed to create TLS trust policy\n");
    goto cleanup;
  }

  OSStatus status =
      SecTrustCreateWithCertificates(certificates, policy, &trust);
  if (status != errSecSuccess || trust == NULL) {
    fprintf(stderr, "Failed to create TLS trust object\n");
    goto cleanup;
  }

  valid = SecTrustEvaluateWithError(trust, &trust_error) ? 1 : 0;
  if (!valid) {
    if (trust_error == NULL) {
      fprintf(
          stderr,
          "TLS certificate trust evaluation failed without error details\n");
    } else {
      CFStringRef domain = CFErrorGetDomain(trust_error);
      CFIndex code = CFErrorGetCode(trust_error);
      char domain_buffer[256];
      const char* domain_string = "unknown";
      if (domain != NULL &&
          CFStringGetCString(domain, domain_buffer, sizeof(domain_buffer),
                             kCFStringEncodingUTF8)) {
        domain_string = domain_buffer;
      }
      fprintf(stderr,
              "TLS certificate trust evaluation failed: domain=%s, code=%ld\n",
              domain_string, (long)code);
    }
  }

cleanup:
  if (trust_error != NULL) {
    CFRelease(trust_error);
  }
  if (trust != NULL) {
    CFRelease(trust);
  }
  if (policy != NULL) {
    CFRelease(policy);
  }
  CFRelease(certificates);
  return valid;
}

// verifier は user_data を保持しないが、libwebrtc-c の callback は必須。
static void sora_apple_destroy_tls_certificate_verifier(void* user_data) {
  (void)user_data;
}

/*
 * Apple のシステム信頼ストアを利用する verifier を PeerConnection へ設定する。
 *
 * webrtc_PeerConnectionDependencies_set_tls_cert_verifier は verifier の所有権を
 * PeerConnectionDependencies へ移す。
 */
__attribute__((visibility("default"))) void
sora_apple_set_system_tls_cert_verifier(
    struct webrtc_PeerConnectionDependencies* dependencies) {
  if (dependencies == NULL) {
    fprintf(stderr, "PeerConnection dependencies are null\n");
    return;
  }

  struct webrtc_SSLCertificateVerifier_cbs callbacks = {
      .VerifyChain = sora_apple_verify_tls_certificate_chain,
      .OnDestroy = sora_apple_destroy_tls_certificate_verifier,
  };
  struct webrtc_SSLCertificateVerifier_unique* verifier =
      webrtc_SSLCertificateVerifier_new(&callbacks, NULL);
  if (verifier == NULL) {
    fprintf(stderr, "Failed to create Apple TLS certificate verifier\n");
    return;
  }

  webrtc_PeerConnectionDependencies_set_tls_cert_verifier(dependencies,
                                                          verifier);
}
