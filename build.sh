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
    <uses-permission android:name="android.permission.READ_CONTACTS" />
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
        <package android:name="com.openai.chatgpt" />
        <package android:name="com.google.android.apps.bard" />
        <package android:name="ai.x.grok" />
        <package android:name="com.anthropic.claude" />
        <package android:name="ai.perplexity.app.android" />
        <package android:name="com.microsoft.copilot" />
        <package android:name="com.deepseek.chat" />
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>
    </queries>

    <application
        android:label="Codex AI"
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
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#03050D"
        android:pathData="M0,0h108v108h-108z" />
    <path android:pathData="M54,54m-24,0a24,24 0 1,1 48,0a24,24 0 1,1 -48,0">
        <aapt:attr name="android:fillColor">
            <gradient
                android:startX="30"
                android:startY="30"
                android:endX="78"
                android:endY="78"
                android:type="linear">
                <item android:offset="0" android:color="#00E5FF" />
                <item android:offset="0.55" android:color="#7C5CFF" />
                <item android:offset="1" android:color="#FF3DF0" />
            </gradient>
        </aapt:attr>
    </path>
    <path
        android:fillColor="#00000000"
        android:strokeColor="#00E5FF"
        android:strokeWidth="2"
        android:pathData="M54,54m-36,0a36,36 0 1,1 72,0a36,36 0 1,1 -72,0" />
</vector>
EOF

cat > android/app/src/main/java/com/cboom/ai/MainActivity.java <<'EOF'
package com.cboom.ai;

import android.Manifest;
import android.app.Activity;
import android.app.SearchManager;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.database.Cursor;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.media.AudioManager;
import android.media.MediaRecorder;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Bundle;
import android.provider.AlarmClock;
import android.provider.ContactsContract;
import android.provider.MediaStore;
import android.provider.Settings;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.speech.tts.Voice;
import android.telephony.PhoneNumberUtils;
import android.telephony.TelephonyManager;
import android.util.Base64;
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
                Manifest.permission.CALL_PHONE,
                Manifest.permission.READ_CONTACTS
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
                    i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, recLang);
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
                    String label = "Codex AI";
                    String aa = arg;
                    int bar = arg.indexOf('|');
                    if (bar >= 0) {
                        label = arg.substring(bar + 1);
                        aa = arg.substring(0, bar);
                    }
                    String[] p = aa.split(":");
                    Intent i = new Intent(AlarmClock.ACTION_SET_ALARM);
                    i.putExtra(AlarmClock.EXTRA_HOUR, Integer.parseInt(p[0]));
                    i.putExtra(AlarmClock.EXTRA_MINUTES, Integer.parseInt(p[1]));
                    i.putExtra(AlarmClock.EXTRA_MESSAGE, label);
                    i.putExtra(AlarmClock.EXTRA_SKIP_UI, true);
                    startNew(i);
                    return "ok";
                }
                if (cmd.equals("timer")) {
                    String label = "Codex AI";
                    String tt = arg;
                    int bar = arg.indexOf('|');
                    if (bar >= 0) {
                        label = arg.substring(bar + 1);
                        tt = arg.substring(0, bar);
                    }
                    Intent i = new Intent(AlarmClock.ACTION_SET_TIMER);
                    i.putExtra(AlarmClock.EXTRA_LENGTH, Integer.parseInt(tt));
                    i.putExtra(AlarmClock.EXTRA_MESSAGE, label);
                    i.putExtra(AlarmClock.EXTRA_SKIP_UI, true);
                    startNew(i);
                    return "ok";
                }
                if (cmd.equals("music")) {
                    try {
                        Intent mi = new Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH);
                        mi.putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*");
                        mi.putExtra(SearchManager.QUERY, arg);
                        startNew(mi);
                        return "ok";
                    } catch (Exception ex) {
                        openExternal("https://www.youtube.com/results?search_query=" + Uri.encode(arg));
                        return "web";
                    }
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
        public String contact(String name) {
            try {
                if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
                    return "denied";
                }
                String q = name.toLowerCase(Locale.ROOT).trim();
                Cursor c = getContentResolver().query(
                        ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                        new String[]{
                                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                                ContactsContract.CommonDataKinds.Phone.NUMBER},
                        null, null, null);
                if (c == null) {
                    return "";
                }
                String bestName = "";
                String bestNum = "";
                int bestScore = 0;
                while (c.moveToNext()) {
                    String n = c.getString(0);
                    String num = c.getString(1);
                    if (n == null || num == null) {
                        continue;
                    }
                    String l = n.toLowerCase(Locale.ROOT);
                    int score = 0;
                    if (l.equals(q)) {
                        score = 3;
                    } else if (l.startsWith(q)) {
                        score = 2;
                    } else if (l.contains(q)) {
                        score = 1;
                    }
                    if (score > bestScore) {
                        bestScore = score;
                        bestName = n;
                        bestNum = num;
                    }
                }
                c.close();
                if (bestScore == 0) {
                    return "";
                }
                String iso = "";
                try {
                    TelephonyManager tm = (TelephonyManager) getSystemService(Context.TELEPHONY_SERVICE);
                    iso = tm.getSimCountryIso();
                } catch (Exception ignore) {
                    iso = "";
                }
                if (iso == null || iso.length() == 0) {
                    iso = Locale.getDefault().getCountry();
                }
                String clean = bestNum.replaceAll("[^0-9+]", "");
                String e164 = PhoneNumberUtils.formatNumberToE164(bestNum, iso.toUpperCase(Locale.ROOT));
                if (e164 == null) {
                    e164 = clean;
                }
                return bestName + "|" + clean + "|" + e164;
            } catch (Exception e) {
                return "";
            }
        }

        private MediaRecorder recorder;
        private java.io.File sample;

        @JavascriptInterface
        public String recStart() {
            try {
                if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    return "denied";
                }
                if (recorder != null) {
                    try {
                        recorder.release();
                    } catch (Exception ignore) {
                        // already released
                    }
                    recorder = null;
                }
                sample = new java.io.File(getCacheDir(), "voice_sample.m4a");
                recorder = new MediaRecorder();
                recorder.setAudioSource(MediaRecorder.AudioSource.MIC);
                recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
                recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
                recorder.setAudioEncodingBitRate(128000);
                recorder.setAudioSamplingRate(44100);
                recorder.setOutputFile(sample.getAbsolutePath());
                recorder.prepare();
                recorder.start();
                return "ok";
            } catch (Exception e) {
                recorder = null;
                return "error";
            }
        }

        @JavascriptInterface
        public String recStop() {
            try {
                if (recorder != null) {
                    recorder.stop();
                    recorder.release();
                    recorder = null;
                    return "ok";
                }
            } catch (Exception e) {
                recorder = null;
            }
            return "error";
        }

        private String readAll(java.io.InputStream is) throws Exception {
            if (is == null) {
                return "";
            }
            java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = is.read(buf)) > 0) {
                bo.write(buf, 0, n);
            }
            return bo.toString("UTF-8");
        }

        private byte[] readBytes(java.io.InputStream is) throws Exception {
            java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = is.read(buf)) > 0) {
                bo.write(buf, 0, n);
            }
            return bo.toByteArray();
        }

        @JavascriptInterface
        public void cloneVoice(final String id, final String name, final String key) {
            new Thread(new Runnable() {
                @Override
                public void run() {
                    int status = 0;
                    String text = "";
                    try {
                        if (sample == null || !sample.exists()) {
                            throw new Exception("No recording yet.");
                        }
                        String boundary = "----CodexAI" + System.nanoTime();
                        java.net.HttpURLConnection c = (java.net.HttpURLConnection) new java.net.URL("https://api.elevenlabs.io/v1/voices/add").openConnection();
                        c.setRequestMethod("POST");
                        c.setConnectTimeout(20000);
                        c.setReadTimeout(60000);
                        c.setDoOutput(true);
                        c.setRequestProperty("xi-api-key", key);
                        c.setRequestProperty("Content-Type", "multipart/form-data; boundary=" + boundary);
                        java.io.OutputStream os = c.getOutputStream();
                        String p1 = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\n" + name + "\r\n";
                        os.write(p1.getBytes("UTF-8"));
                        String p2 = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"files\"; filename=\"sample.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n";
                        os.write(p2.getBytes("UTF-8"));
                        java.io.FileInputStream fis = new java.io.FileInputStream(sample);
                        byte[] buf = new byte[8192];
                        int n;
                        while ((n = fis.read(buf)) > 0) {
                            os.write(buf, 0, n);
                        }
                        fis.close();
                        os.write(("\r\n--" + boundary + "--\r\n").getBytes("UTF-8"));
                        os.close();
                        status = c.getResponseCode();
                        text = readAll(status >= 400 ? c.getErrorStream() : c.getInputStream());
                    } catch (Exception e) {
                        status = 0;
                        text = String.valueOf(e.getMessage());
                    }
                    js("nativeHttp(" + JSONObject.quote(id) + "," + status + "," + JSONObject.quote(text) + ")");
                }
            }).start();
        }

        @JavascriptInterface
        public void httpBin(final String id, final String url, final String headersJson, final String body) {
            new Thread(new Runnable() {
                @Override
                public void run() {
                    int status = 0;
                    String text = "";
                    try {
                        java.net.HttpURLConnection c = (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
                        c.setRequestMethod("POST");
                        c.setConnectTimeout(15000);
                        c.setReadTimeout(40000);
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
                        if (status >= 200 && status < 300) {
                            byte[] data = readBytes(c.getInputStream());
                            text = Base64.encodeToString(data, Base64.NO_WRAP);
                        } else {
                            text = readAll(c.getErrorStream());
                        }
                    } catch (Exception e) {
                        status = 0;
                        text = "";
                    }
                    js("nativeHttp(" + JSONObject.quote(id) + "," + status + "," + JSONObject.quote(text) + ")");
                }
            }).start();
        }

        private String recLang = "en-US";

        @JavascriptInterface
        public void setLang(String l) {
            if (l != null && l.length() > 0) {
                recLang = l;
            }
        }

        @JavascriptInterface
        public String askApp(final String pkg, final String text, final String webUrl) {
            try {
                ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                cm.setPrimaryClip(ClipData.newPlainText("Codex AI", text));
            } catch (Exception ignore) {
                // clipboard not available
            }
            try {
                Intent i = new Intent(Intent.ACTION_SEND);
                i.setType("text/plain");
                i.putExtra(Intent.EXTRA_TEXT, text);
                i.setPackage(pkg);
                startNew(i);
                return "shared";
            } catch (Exception e) {
                try {
                    Intent li = getPackageManager().getLaunchIntentForPackage(pkg);
                    if (li != null) {
                        startNew(li);
                        return "launched";
                    }
                } catch (Exception e2) {
                    // fall through to the web
                }
                openExternal(webUrl);
                return "web";
            }
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

# built-in AI key, read from the GEMINI_KEY secret (never stored in the repo)
python3 - <<'PYIN'
import json, os
key = os.environ.get("GEMINI_KEY", "")
open("android/app/src/main/assets/config.js", "w").write("window.DEFAULT_KEY=" + json.dumps(key) + ";\n")
PYIN

cd android
gradle assembleDebug --no-daemon --stacktrace
cd ..
cp android/app/build/outputs/apk/debug/app-debug.apk build-out/CboomAI.apk
ls -la build-out
