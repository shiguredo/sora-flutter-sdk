# WebRTC M149 以降の `org.jni_zero.JniZero` は、class loader の初期化時に
# 生成クラス `org.jni_zero.JniZeroJni` を参照する。
# 現在利用している WebRTC の `webrtc.jar` にはこの生成クラスが含まれていないため、
# R8 はこの参照先を Missing class として検出し、release build を失敗させる。
# これを抑制するために dontwarn を設定する
-dontwarn org.jni_zero.**
