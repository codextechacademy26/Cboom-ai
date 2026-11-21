#!/bin/bash
# Builds the Cboom AI Android app from cboom-ai.html (run by GitHub Actions)
set -e

rm -rf android build-out
mkdir -p android/app/src/main/java/com/cboom/ai android/app/src/main/assets android/app/src/main/res/drawable build-out

cat > android/settings.gradle <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "CboomAI"
include ':app'
EOF

cat > android/build.gradle <<'EOF'
plugins {
    id 'com.android.application' version '8.5.2' apply false
}
EOF

cat > android/gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2g
android.nonTransitiveRClass=true
EOF

cat > android/app/build.gradle <<'EOF'
plugins {
    id 'com.android.application'
}

android {
    namespace 'com.cboom.ai'
    compileSdk 34

    defaultConfig {
        applicationId "com.cboom.ai"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
EOF

cat > android/app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.CALL_PHONE" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <uses-permission android:name="com.android.alarm.permission.SET_ALARM" />

    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>
    </queries>

    <application
        android:label="Cboom AI"
        android:icon="@drawable/ic_launcher"
        android:allowBackup="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:theme="@android:style/Theme.DeviceDefault.NoActionBar"
            android:windowSoftInputMode="adjustResize"
            android:configChanges="orientation|screenSize|keyboardHidden|smallestScreenSize|screenLayout|density">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

cat > android/app/src/main/res/drawable/ic_launcher.xml <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#050007"
        android:pathData="M0,0h108v108h-108z" />
    <path
        android:fillColor="#FF2A52"
        android:pathData="M54,54m-28,0a28,28 0 1,1 56,0a28,28 0 1,1 -56,0" />
</vector>
EOF

cat > android/app/src/main/java/com/cboom/ai/MainActivity.java <<'EOF'
package com.cboom.ai;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.media.AudioManager;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Bundle;
import android.provider.AlarmClock;
import android.provider.MediaStore;
import android.provider.Settings;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.speech.tts.Voice;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public class MainActivity extends Activity {

    private WebView web;
    private TextToSpeech tts;
    private boolean ttsReady = false;
    private SpeechRecognizer recognizer;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        web = new WebView(this);
        setContentView(web);
        web.setBackgroundColor(0xFF050007);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);

        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                String u = request.getUrl().toString();
                if (u.startsWith("file:")) {
                    return false;
                }
                openExternal(u);
                return true;
            }
        });
        web.addJavascriptInterface(new Bridge(), "Android");

        tts = new TextToSpeech(this, new TextToSpeech.OnInitListener() {
            @Override
            public void onInit(int status) {
                ttsReady = (status == TextToSpeech.SUCCESS);
                if (ttsReady) {
                    tts.setLanguage(Locale.US);
                    tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                        @Override
                        public void onStart(String id) {
                            js("nativeSpeakStart()");
                        }

                        @Override
                        public void onDone(String id) {
                            js("nativeSpeakEnd()");
                        }

                        @Override
                        public void onError(String id) {
                            js("nativeSpeakEnd()");
                        }
                    });
                }
            }
        });

        requestPermissions(new String[]{
                Manifest.permission.RECORD_AUDIO,
                Manifest.permission.CALL_PHONE
        }, 1);

        web.loadUrl("file:///android_asset/index.html");
    }

    private void js(final String code) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                web.evaluateJavascript("try{" + code + "}catch(e){}", null);
            }
        });
    }

    private void openExternal(final String url) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(i);
                } catch (Exception e) {
                    // nothing can open this link
                }
            }
        });
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (recognizer != null) {
            recognizer.destroy();
        }
        if (tts != null) {
            tts.stop();
            tts.shutdown();
        }
    }

    class Bridge {

        @JavascriptInterface
        public boolean isNative() {
            return true;
        }

        @JavascriptInterface
        public String getVoices() {
            JSONArray arr = new JSONArray();
            try {
                if (tts != null && ttsReady) {
                    Set<Voice> vs = tts.getVoices();
                    if (vs != null) {
                        List<Voice> list = new ArrayList<Voice>();
                        for (Voice v : vs) {
                            if ("en".equals(v.getLocale().getLanguage())) {
                                list.add(v);
                            }
                        }
                        Collections.sort(list, new java.util.Comparator<Voice>() {
                            @Override
                            public int compare(Voice a, Voice b) {
                                return a.getName().compareTo(b.getName());
                            }
                        });
                        int n = 1;
                        for (Voice v : list) {
                            JSONObject o = new JSONObject();
                            o.put("name", v.getName());
                            o.put("label", "Voice " + n + " - " + v.getLocale().getDisplayName()
                                    + (v.isNetworkConnectionRequired() ? " (online)" : ""));
                            arr.put(o);
                            n++;
                        }
                    }
                }
            } catch (Exception e) {
                // return what we have
            }
            return arr.toString();
        }

        @JavascriptInterface
        public void speak(final String text, final String voice, final float pitch, final float rate) {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    if (tts == null || !ttsReady) {
                        js("nativeSpeakEnd()");
                        return;
                    }
                    try {
                        if (voice != null && voice.length() > 0) {
                            Set<Voice> vs = tts.getVoices();
                            if (vs != null) {
                                for (Voice v : vs) {
                                    if (v.getName().equals(voice)) {
                                        tts.setVoice(v);
                                        break;
                                    }
                                }
                            }
                        }
                        tts.setPitch(pitch);
                        tts.setSpeechRate(rate);
                        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "u" + System.nanoTime());
                    } catch (Exception e) {
                        js("nativeSpeakEnd()");
                    }
                }
            });
        }

        @JavascriptInterface
        public void stopSpeak() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    if (tts != null) {
                        tts.stop();
                    }
                }
            });
        }

        @JavascriptInterface
        public void listen() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 2);
                        js("nativeError('blocked')");
                        return;
                    }
                    if (!SpeechRecognizer.isRecognitionAvailable(MainActivity.this)) {
                        js("nativeError('unavailable')");
                        return;
                    }
                    if (recognizer != null) {
                        recognizer.destroy();
                    }
                    recognizer = SpeechRecognizer.createSpeechRecognizer(MainActivity.this);
                    recognizer.setRecognitionListener(new RecognitionListener() {
                        @Override
                        public void onReadyForSpeech(Bundle params) {
                            js("nativeListening()");
                        }

                        @Override
                        public void onBeginningOfSpeech() {
                        }

                        @Override
                        public void onRmsChanged(float rmsdB) {
                        }

                        @Override
                        public void onBufferReceived(byte[] buffer) {
                        }

                        @Override
                        public void onEndOfSpeech() {
                        }

                        @Override
                        public void onError(int error) {
                            String c = "other";
                            if (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                                c = "none";
                            } else if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                                c = "blocked";
                            }
                            js("nativeError('" + c + "')");
                        }

                        @Override
                        public void onResults(Bundle results) {
                            ArrayList<String> l = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                            if (l != null && l.size() > 0) {
                                js("nativeResult(" + JSONObject.quote(l.get(0)) + ")");
                            } else {
                                js("nativeError('none')");
                            }
                        }

                        @Override
                        public void onPartialResults(Bundle partialResults) {
                            ArrayList<String> l = partialResults.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                            if (l != null && l.size() > 0) {
                                js("nativePartial(" + JSONObject.quote(l.get(0)) + ")");
                            }
                        }

                        @Override
                        public void onEvent(int eventType, Bundle params) {
                        }
                    });
                    Intent i = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
                    i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
                    i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US");
                    i.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
                    recognizer.startListening(i);
                }
            });
        }

        @JavascriptInterface
        public void stopListen() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    if (recognizer != null) {
                        recognizer.stopListening();
                    }
                }
            });
        }

        @JavascriptInterface
        public void call(final String number) {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    try {
                        boolean ok = checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED;
                        Intent i = new Intent(ok ? Intent.ACTION_CALL : Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(number)));
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(i);
                    } catch (Exception e) {
                        // could not start the call
                    }
                }
            });
        }

        @JavascriptInterface
        public boolean sms(String number, String body) {
            String u = "sms:" + number;
            if (body != null && body.length() > 0) {
                u += "?body=" + Uri.encode(body);
            }
            openExternal(u);
            return true;
        }

        @JavascriptInterface
        public void openUrl(String url) {
            openExternal(url);
        }

        private boolean torchOn = false;

        private void startNew(Intent i) {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        }

        private String torch(String arg) throws Exception {
            CameraManager cm = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            String id = null;
            for (String c : cm.getCameraIdList()) {
                CameraCharacteristics ch = cm.getCameraCharacteristics(c);
                Boolean flash = ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
                Integer facing = ch.get(CameraCharacteristics.LENS_FACING);
                if (Boolean.TRUE.equals(flash) && facing != null && facing == CameraCharacteristics.LENS_FACING_BACK) {
                    id = c;
                    break;
                }
            }
            if (id == null) {
                return "none";
            }
            boolean on = arg.equals("on") || (arg.equals("toggle") && !torchOn);
            cm.setTorchMode(id, on);
            torchOn = on;
            return on ? "on" : "off";
        }

        private String volume(String arg) {
            AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            int max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
            int cur = am.getStreamVolume(AudioManager.STREAM_MUSIC);
            int step = Math.max(1, max / 6);
            int v = cur;
            if (arg.equals("up")) {
                v = Math.min(max, cur + step);
            } else if (arg.equals("down")) {
                v = Math.max(0, cur - step);
            } else if (arg.equals("max")) {
                v = max;
            } else if (arg.equals("mute")) {
                v = 0;
            } else {
                try {
                    int pct = Math.min(100, Math.max(0, Integer.parseInt(arg)));
                    v = Math.round(max * pct / 100f);
                } catch (Exception e) {
                    v = cur;
                }
            }
            am.setStreamVolume(AudioManager.STREAM_MUSIC, v, AudioManager.FLAG_SHOW_UI);
            return String.valueOf(Math.round(100f * v / max));
        }

        @JavascriptInterface
        public String device(String cmd, String arg) {
            try {
                if (cmd.equals("torch")) {
                    return torch(arg);
                }
                if (cmd.equals("volume")) {
                    return volume(arg);
                }
                if (cmd.equals("alarm")) {
                    String[] p = arg.split(":");
                    Intent i = new Intent(AlarmClock.ACTION_SET_ALARM);
                    i.putExtra(AlarmClock.EXTRA_HOUR, Integer.parseInt(p[0]));
                    i.putExtra(AlarmClock.EXTRA_MINUTES, Integer.parseInt(p[1]));
                    i.putExtra(AlarmClock.EXTRA_MESSAGE, "Cboom AI");
                    i.putExtra(AlarmClock.EXTRA_SKIP_UI, true);
                    startNew(i);
                    return "ok";
                }
                if (cmd.equals("timer")) {
                    Intent i = new Intent(AlarmClock.ACTION_SET_TIMER);
                    i.putExtra(AlarmClock.EXTRA_LENGTH, Integer.parseInt(arg));
                    i.putExtra(AlarmClock.EXTRA_MESSAGE, "Cboom AI");
                    i.putExtra(AlarmClock.EXTRA_SKIP_UI, true);
                    startNew(i);
                    return "ok";
                }
                if (cmd.equals("battery")) {
                    Intent b = registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
                    int level = b.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                    int scale = b.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
                    int status = b.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
                    boolean charging = status == BatteryManager.BATTERY_STATUS_CHARGING
                            || status == BatteryManager.BATTERY_STATUS_FULL;
                    return (level * 100 / scale) + (charging ? ",charging" : ",not charging");
                }
                if (cmd.equals("wifi")) {
                    startNew(new Intent(Settings.ACTION_WIFI_SETTINGS));
                    return "ok";
                }
                if (cmd.equals("bluetooth")) {
                    startNew(new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
                    return "ok";
                }
                if (cmd.equals("camera")) {
                    startNew(new Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA));
                    return "ok";
                }
            } catch (Exception e) {
                return "error";
            }
            return "";
        }

        @JavascriptInterface
        public void http(final String id, final String url, final String headersJson, final String body) {
            new Thread(new Runnable() {
                @Override
                public void run() {
                    int status = 0;
                    String text = "";
                    try {
                        java.net.HttpURLConnection c = (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
                        c.setRequestMethod("POST");
                        c.setConnectTimeout(15000);
                        c.setReadTimeout(25000);
                        c.setDoOutput(true);
                        JSONObject h = new JSONObject(headersJson);
                        java.util.Iterator<String> it = h.keys();
                        while (it.hasNext()) {
                            String k = it.next();
                            c.setRequestProperty(k, h.getString(k));
                        }
                        java.io.OutputStream os = c.getOutputStream();
                        os.write(body.getBytes("UTF-8"));
                        os.close();
                        status = c.getResponseCode();
                        java.io.InputStream is = status >= 400 ? c.getErrorStream() : c.getInputStream();
                        if (is != null) {
                            java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
                            byte[] buf = new byte[4096];
                            int n;
                            while ((n = is.read(buf)) > 0) {
                                bo.write(buf, 0, n);
                            }
                            text = bo.toString("UTF-8");
                        }
                    } catch (Exception e) {
                        status = 0;
                        text = "";
                    }
                    js("nativeHttp(" + JSONObject.quote(id) + "," + status + "," + JSONObject.quote(text) + ")");
                }
            }).start();
        }

        @JavascriptInterface
        public String openApp(String name) {
            try {
                PackageManager pm = getPackageManager();
                String q = name.toLowerCase(Locale.ROOT).trim();
                if (q.contains(".") && !q.contains(" ")) {
                    Intent direct = pm.getLaunchIntentForPackage(q);
                    if (direct != null) {
                        direct.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(direct);
                        return q;
                    }
                }
                Intent main = new Intent(Intent.ACTION_MAIN);
                main.addCategory(Intent.CATEGORY_LAUNCHER);
                List<ResolveInfo> list = pm.queryIntentActivities(main, 0);
                ResolveInfo best = null;
                String bestLabel = "";
                for (ResolveInfo r : list) {
                    String label = r.loadLabel(pm).toString();
                    String l = label.toLowerCase(Locale.ROOT);
                    if (l.equals(q)) {
                        best = r;
                        bestLabel = label;
                        break;
                    }
                    if (best == null && l.length() > 2 && (l.contains(q) || q.contains(l))) {
                        best = r;
                        bestLabel = label;
                    }
                }
                if (best != null) {
                    Intent li = pm.getLaunchIntentForPackage(best.activityInfo.packageName);
                    if (li != null) {
                        li.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(li);
                        return bestLabel;
                    }
                }
            } catch (Exception e) {
                // fall through
            }
            return "";
        }
    }
}
EOF

# put the web app inside the Android app
cp cboom-ai.html android/app/src/main/assets/index.html

cd android
gradle assembleDebug --no-daemon --stacktrace
cd ..
cp android/app/build/outputs/apk/debug/app-debug.apk build-out/CboomAI.apk
ls -la build-out
