package com.nexus.mastersync.adb;

import android.content.ClipData;
import android.content.ClipDescription;
import android.content.ClipboardManager;
import android.content.ContentResolver;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Looper;
import android.os.PersistableBundle;

import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

public final class NexusUsbClipboard {
    private static final String BACKGROUND_CLIPBOARD = "android.permission.READ_CLIPBOARD_IN_BACKGROUND";
    private static final int TEXT_LIMIT = 32 * 1024;
    private static final int IMAGE_LIMIT = 8 * 1024 * 1024;
    private static final Set<String> IMAGE_TYPES = new HashSet<>(Arrays.asList(
            "image/png", "image/jpeg", "image/gif", "image/webp", "image/heic", "image/heif"));

    private final ClipboardManager clipboard;
    private final DataOutputStream output = new DataOutputStream(new BufferedOutputStream(System.out));
    private long lastTimestamp;

    private NexusUsbClipboard(ClipboardManager clipboard) {
        this.clipboard = clipboard;
    }

    public static void main(String[] args) throws Exception {
        // app_process is launched by the authorized ADB shell, without an installed APK.
        Looper.prepareMainLooper();
        Context shell = shellContext();
        if (shell.checkSelfPermission(BACKGROUND_CLIPBOARD) != PackageManager.PERMISSION_GRANTED) {
            System.exit(4);
        }
        ClipboardManager manager = shell.getSystemService(ClipboardManager.class);
        // The framework also checks that the package name belongs to the calling UID.
        Context owner = new ContextWrapper(shell) {
            @Override public String getOpPackageName() { return "com.android.shell"; }
        };
        setField(ClipboardManager.class, "mContext", manager, owner);
        new NexusUsbClipboard(manager).run();
    }

    private static Context shellContext() throws ReflectiveOperationException, PackageManager.NameNotFoundException {
        Class<?> type = Class.forName("android.app.ActivityThread");
        Constructor<?> constructor = type.getDeclaredConstructor();
        constructor.setAccessible(true);
        Object thread = constructor.newInstance();
        setField(type, "sCurrentActivityThread", null, thread);
        if (Build.VERSION.SDK_INT >= 31) {
            Class<?> controller = Class.forName("android.app.ConfigurationController");
            Constructor<?> init = controller.getDeclaredConstructor(Class.forName("android.app.ActivityThreadInternal"));
            init.setAccessible(true);
            setField(type, "mConfigurationController", thread, init.newInstance(thread));
        }
        Context system = (Context) type.getMethod("getSystemContext").invoke(thread);
        return system.createPackageContext("com.android.shell", 0);
    }

    private static void setField(Class<?> type, String name, Object target, Object value) throws ReflectiveOperationException {
        Field field = type.getDeclaredField(name);
        field.setAccessible(true);
        field.set(target, value);
    }

    private void run() throws IOException {
        Thread connection = new Thread(() -> {
            try { while (System.in.read() != -1) { } }
            catch (IOException ignored) { }
            // Closing the Mac's ADB pipe also stops the phone-side listener.
            System.exit(0);
        }, "adb-connection");
        connection.setDaemon(true);
        connection.start();
        ClipDescription initial = clipboard.getPrimaryClipDescription();
        lastTimestamp = initial == null ? 0 : initial.getTimestamp();
        clipboard.addPrimaryClipChangedListener(this::changed);
        output.writeInt(0x4E584331); // NXC1
        output.flush();
        Looper.loop();
    }

    private void changed() {
        ClipDescription description = clipboard.getPrimaryClipDescription();
        if (description == null || excluded(description) || description.getTimestamp() == lastTimestamp) return;
        ClipData clip = clipboard.getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0 || excluded(clip.getDescription())) return;
        lastTimestamp = clip.getDescription().getTimestamp();
        ClipData.Item item = clip.getItemAt(0);
        Uri uri = item.getUri();
        if (uri != null && ContentResolver.SCHEME_CONTENT.equals(uri.getScheme())
                && clip.getDescription().hasMimeType("image/*")) {
            for (int i = 0; i < clip.getDescription().getMimeTypeCount(); i++) {
                String mime = clip.getDescription().getMimeType(i);
                if (IMAGE_TYPES.contains(mime)) {
                    sendImage(uri, mime);
                    break;
                }
            }
        } else if (item.getText() != null && item.getText().length() <= TEXT_LIMIT) {
            byte[] bytes = item.getText().toString().getBytes(StandardCharsets.UTF_8);
            if (bytes.length > 0 && bytes.length <= TEXT_LIMIT) emit(1, new byte[0], bytes);
        }
    }

    private void sendImage(Uri uri, String mime) {
        java.lang.Process reader = null;
        try {
            reader = new ProcessBuilder("/system/bin/content", "read", "--uri", uri.toString())
                    .redirectError(new File("/dev/null")).start();
            try (InputStream input = reader.getInputStream()) {
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                byte[] buffer = new byte[64 * 1024];
                for (int count; (count = input.read(buffer)) != -1; ) {
                    if (bytes.size() + count > IMAGE_LIMIT) return;
                    bytes.write(buffer, 0, count);
                }
                byte[] type = mime.getBytes(StandardCharsets.US_ASCII);
                if (reader.waitFor() == 0 && bytes.size() > 0) emit(2, type, bytes.toByteArray());
            }
        } catch (IOException | InterruptedException | RuntimeException ignored) {
            // Some apps revoke access to the URI before the recipient can read it.
        } finally {
            if (reader != null) reader.destroy();
        }
    }

    private void emit(int kind, byte[] mime, byte[] bytes) {
        try {
            output.writeByte(kind);
            output.writeInt(bytes.length + (kind == 2 ? mime.length + 1 : 0));
            if (kind == 2) {
                output.writeByte(mime.length);
                output.write(mime);
            }
            output.write(bytes);
            output.flush();
        } catch (IOException error) {
            System.exit(0);
        }
    }

    private static boolean excluded(ClipDescription description) {
        PersistableBundle extras = description.getExtras();
        return extras != null && (extras.getBoolean("android.content.extra.IS_SENSITIVE")
                || extras.getBoolean("com.nexus.mastersync.clipboard.REMOTE"));
    }
}
