## 0.1.0

* Updates the minimum supported SDK version to Flutter 3.44/Dart 3.12.
* Migrates to built-in Kotlin (AGP 9+). Apps must set `android.builtInKotlin=true`.
* Removes the global `-dontobfuscate` from the consumer ProGuard rules (not allowed in consumer files on AGP 9+). Apps that relied on it must add it to their own rules.

## 0.0.1

* TODO: Describe initial release.
