package io.github.spartan1203.rpocket;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    static final String TERMUX = "com.termux";
    static final String RUN_COMMAND_PERMISSION = "com.termux.permission.RUN_COMMAND";
    static final String TERMUX_HOME = "/data/data/com.termux/files/home";
    static final int PORT = 8790;
    static final int PERMISSION_REQUEST = 42;

    private WebView web;
    private String token;
    private final ExecutorService pool = Executors.newCachedThreadPool();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        token = loadToken();

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient());
        web.addJavascriptInterface(new Bridge(), "RBridge");
        setContentView(web);
        web.loadUrl("file:///android_asset/index.html");
    }

    private String loadToken() {
        SharedPreferences prefs = getSharedPreferences("rpocket", MODE_PRIVATE);
        String t = prefs.getString("token", null);
        if (t == null) {
            byte[] b = new byte[16];
            new SecureRandom().nextBytes(b);
            StringBuilder sb = new StringBuilder();
            for (byte x : b) sb.append(String.format("%02x", x));
            t = sb.toString();
            prefs.edit().putString("token", t).apply();
        }
        return t;
    }

    private void callJs(final String fn, final String... args) {
        final StringBuilder sb = new StringBuilder("window.").append(fn).append("(");
        for (int i = 0; i < args.length; i++) {
            if (i > 0) sb.append(",");
            sb.append(args[i]);
        }
        sb.append(")");
        runOnUiThread(() -> web.evaluateJavascript(sb.toString(), null));
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode == PERMISSION_REQUEST) {
            boolean ok = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
            callJs("onPermissionResult", ok ? "true" : "false");
        }
    }

    @Override
    public void onBackPressed() {
        web.evaluateJavascript("window.handleBack && window.handleBack()", value -> {
            if (!"true".equals(value)) MainActivity.super.onBackPressed();
        });
    }

    @Override
    protected void onDestroy() {
        pool.shutdownNow();
        super.onDestroy();
    }

    class Bridge {
        @JavascriptInterface
        public boolean termuxInstalled() {
            try {
                getPackageManager().getPackageInfo(TERMUX, 0);
                return true;
            } catch (PackageManager.NameNotFoundException e) {
                return false;
            }
        }

        @JavascriptInterface
        public boolean hasPermission() {
            return checkSelfPermission(RUN_COMMAND_PERMISSION) == PackageManager.PERMISSION_GRANTED;
        }

        @JavascriptInterface
        public void requestPermission() {
            runOnUiThread(() -> requestPermissions(new String[]{RUN_COMMAND_PERMISSION}, PERMISSION_REQUEST));
        }

        @JavascriptInterface
        public String startR() {
            Intent i = new Intent();
            i.setClassName(TERMUX, "com.termux.app.RunCommandService");
            i.setAction("com.termux.RUN_COMMAND");
            i.putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash");
            i.putExtra("com.termux.RUN_COMMAND_ARGUMENTS",
                    new String[]{TERMUX_HOME + "/.rpocket/start.sh", token, String.valueOf(PORT)});
            i.putExtra("com.termux.RUN_COMMAND_WORKDIR", TERMUX_HOME);
            i.putExtra("com.termux.RUN_COMMAND_BACKGROUND", true);
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i);
                else startService(i);
                return "";
            } catch (Exception e) {
                return e.getClass().getSimpleName() + ": " + e.getMessage();
            }
        }

        @JavascriptInterface
        public void openTermux() {
            Intent i = getPackageManager().getLaunchIntentForPackage(TERMUX);
            if (i != null) startActivity(i);
        }

        @JavascriptInterface
        public void openUrl(String url) {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        }

        @JavascriptInterface
        public void copyText(String text) {
            android.content.ClipboardManager cm =
                    (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            cm.setPrimaryClip(android.content.ClipData.newPlainText("R Pocket", text));
        }

        // Sends an HTTP request to the R listener; the reply arrives via window.__rb(id, status, body)
        @JavascriptInterface
        public void request(final int id, final String method, final String path,
                            final String body, final boolean binary, final int timeoutMs) {
            pool.execute(() -> {
                int status = 0;
                String out;
                HttpURLConnection c = null;
                try {
                    c = (HttpURLConnection) new URL("http://127.0.0.1:" + PORT + path).openConnection();
                    c.setRequestMethod(method);
                    c.setConnectTimeout(2000);
                    c.setReadTimeout(timeoutMs);
                    c.setRequestProperty("X-Token", token);
                    c.setUseCaches(false);
                    if (body != null && !body.isEmpty()) {
                        byte[] data = body.getBytes(StandardCharsets.UTF_8);
                        c.setDoOutput(true);
                        c.setRequestProperty("Content-Type", "text/plain; charset=utf-8");
                        c.setFixedLengthStreamingMode(data.length);
                        try (OutputStream os = c.getOutputStream()) { os.write(data); }
                    }
                    status = c.getResponseCode();
                    InputStream is = status >= 400 ? c.getErrorStream() : c.getInputStream();
                    byte[] bytes = readAll(is);
                    out = binary ? Base64.encodeToString(bytes, Base64.NO_WRAP)
                                 : new String(bytes, StandardCharsets.UTF_8);
                } catch (Exception e) {
                    out = e.getClass().getSimpleName() + ": " + e.getMessage();
                } finally {
                    if (c != null) c.disconnect();
                }
                callJs("__rb", String.valueOf(id), String.valueOf(status), JSONObject.quote(out));
            });
        }
    }

    static byte[] readAll(InputStream is) throws java.io.IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        if (is == null) return bos.toByteArray();
        byte[] buf = new byte[16384];
        int n;
        while ((n = is.read(buf)) > 0) bos.write(buf, 0, n);
        is.close();
        return bos.toByteArray();
    }
}
