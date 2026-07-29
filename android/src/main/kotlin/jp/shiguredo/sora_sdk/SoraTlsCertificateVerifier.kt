package jp.shiguredo.sora_sdk

import android.util.Log
import java.io.ByteArrayInputStream
import java.security.KeyStore
import java.security.cert.CertPathValidator
import java.security.cert.CertificateFactory
import java.security.cert.CertificateParsingException
import java.security.cert.PKIXParameters
import java.security.cert.TrustAnchor
import java.security.cert.X509Certificate
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

// libwebrtc が受信した TURN-TLS 証明書チェーンを Android の信頼ストアで検証する。
//
// ホスト名検証は libwebrtc の OpenSSLAdapter が別途実行するため、
// ここでは証明書チェーンの信頼性と有効期間だけを検証する。
object SoraTlsCertificateVerifier {
    private const val TAG = "SoraTlsCertificateVerifier"
    private const val OID_SERVER_AUTH = "1.3.6.1.5.5.7.3.1"
    private const val OID_ANY_EXTENDED_KEY_USAGE = "2.5.29.37.0"

    // DER 形式の証明書チェーンを Android の信頼ストアで検証する。
    //
    // WebRTC の network thread から JNI 経由で同期的に呼び出される。
    @JvmStatic
    fun verifyCertificateChain(chain: Array<ByteArray>): Boolean {
        if (chain.isEmpty()) {
            Log.w(TAG, "TLS certificate chain is empty")
            return false
        }

        return try {
            val certificateFactory = CertificateFactory.getInstance("X.509")
            val certificates =
                chain
                    .map { der ->
                        ByteArrayInputStream(der).use { input ->
                            certificateFactory.generateCertificate(input) as X509Certificate
                        }
                    }

            val trustManagerFactory =
                TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
            trustManagerFactory.init(null as KeyStore?)
            val trustManager =
                trustManagerFactory.trustManagers
                    .filterIsInstance<X509TrustManager>()
                    .singleOrNull()

            if (trustManager == null) {
                Log.e(TAG, "Default X509 trust manager is unavailable")
                false
            } else {
                val certPath = certificateFactory.generateCertPath(certificates)
                val trustAnchors =
                    trustManager.acceptedIssuers
                        .map { certificate -> TrustAnchor(certificate, null) }
                        .toSet()
                if (trustAnchors.isEmpty()) {
                    throw IllegalStateException("System trust store is empty")
                }

                // libwebrtc の既定の証明書検証と同様に、CRL / OCSP による失効確認は行わない。
                val pkixParameters =
                    PKIXParameters(trustAnchors).apply {
                        isRevocationEnabled = false
                    }
                CertPathValidator.getInstance("PKIX").validate(certPath, pkixParameters)
                if (!verifyExtendedKeyUsage(certificates)) {
                    throw IllegalStateException("Extended key usage validation failed")
                }
                true
            }
        } catch (_: Exception) {
            // 証明書の内容や接続先をログへ出さず、検証失敗だけを記録する。
            Log.w(TAG, "TLS certificate chain verification failed")
            false
        }
    }

    // 証明書チェーンを構成する全証明書が TLS サーバー用途として利用できることを確認する。
    //
    // EKU 拡張が存在しない証明書は、RFC 5280 に従って用途を制限しない証明書として扱う。
    private fun verifyExtendedKeyUsage(certificates: List<X509Certificate>): Boolean =
        try {
            certificates.all { certificate ->
                val extendedKeyUsage = certificate.extendedKeyUsage ?: return@all true
                extendedKeyUsage.contains(OID_SERVER_AUTH) ||
                    extendedKeyUsage.contains(OID_ANY_EXTENDED_KEY_USAGE)
            }
        } catch (_: CertificateParsingException) {
            Log.w(TAG, "TLS certificate extended key usage parsing failed")
            false
        }
}
