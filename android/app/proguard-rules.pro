# ML Kit text recognition references other script recognizers
# (Chinese, Devanagari, Japanese, Korean) that we don't use.
# Use -dontwarn to tell R8 not to fail the build on those references.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
