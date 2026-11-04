import java.lang.reflect.Constructor;
import java.util.ArrayList;
import java.util.List;

/** Root-only prototype: address Android credential nodes, never global keyboard input. */
public final class CredentialUi {
    static Object automation;
    static Class<?> nodeClass, bundleClass;

    static Object call(Object target, String name) throws Exception {
        return target.getClass().getMethod(name).invoke(target);
    }

    static String string(Object value) {
        return value == null ? "" : value.toString();
    }

    static List<Object> nodes(Object root) throws Exception {
        List<Object> result = new ArrayList<>();
        if (root == null) return result;
        result.add(root);
        int count = (Integer) call(root, "getChildCount");
        for (int i = 0; i < count; i++) {
            Object child = nodeClass.getMethod("getChild", int.class).invoke(root, i);
            result.addAll(nodes(child));
        }
        return result;
    }

    static List<Object> current() throws Exception {
        return nodes(call(automation, "getRootInActiveWindow"));
    }

    static String id(Object node) throws Exception {
        return string(call(node, "getViewIdResourceName"));
    }

    static boolean visible(Object node) throws Exception {
        return (Boolean) call(node, "isVisibleToUser");
    }

    static Object find(List<Object> nodes, String resource) throws Exception {
        for (Object node : nodes) {
            if (resource.equals(id(node)) && visible(node)) return node;
        }
        return null;
    }

    static String packageName(Object node) throws Exception {
        return string(call(node, "getPackageName"));
    }

    static String target(List<Object> nodes) throws Exception {
        for (Object node : nodes) {
            if (!visible(node) || !(Boolean) call(node, "isPassword")) continue;
            String id = id(node);
            String pkg = packageName(node);
            if (pkg.equals("com.android.systemui") && id.equals("com.android.systemui:id/pinEntry")
                    && find(nodes, "com.android.systemui:id/keyguard_pin_view") != null
                    && find(nodes, "com.android.systemui:id/key_enter") != null) {
                for (int i = 0; i < 10; i++) {
                    if (find(nodes, "com.android.systemui:id/key" + i) == null) return "";
                }
                return "keyguard-pin";
            }
            if (pkg.equals("com.android.systemui") && id.equals("com.android.systemui:id/lockPassword")
                    && (Boolean) call(node, "isEditable")) return "systemui-credential";
            if (pkg.equals("com.android.settings") && id.equals("com.android.settings:id/password_entry")
                    && (Boolean) call(node, "isEditable") && settingsConfirmation()) return "settings-credential";
        }
        return "";
    }

    static boolean settingsConfirmation() throws Exception {
        Process process = new ProcessBuilder("/system/bin/dumpsys", "activity", "activities").start();
        try (java.io.BufferedReader reader = new java.io.BufferedReader(
                new java.io.InputStreamReader(process.getInputStream()))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.contains("topResumedActivity=")) {
                    return line.contains("com.android.settings") && line.contains("password.ConfirmLockPassword");
                }
            }
            return false;
        } finally {
            process.destroy();
        }
    }

    static void click(Object node) throws Exception {
        if (node == null || !(Boolean) nodeClass.getMethod("performAction", int.class).invoke(node, 16)) {
            throw new IllegalStateException();
        }
    }

    static void submit(String expected, int windowId, String pin) throws Exception {
        List<Object> fresh = current();
        if (!expected.equals(target(fresh)) || fresh.isEmpty()
                || (Integer) call(fresh.get(0), "getWindowId") != windowId) throw new IllegalStateException();
        if (expected.equals("keyguard-pin")) {
            if (!string(call(find(fresh, "com.android.systemui:id/pinEntry"), "getText")).isEmpty()) {
                throw new IllegalStateException();
            }
            // Each click addresses a node in the credential window. No host or
            // Android global keyboard events are injected if focus changes.
            for (char digit : pin.toCharArray()) {
                fresh = current();
                if (!expected.equals(target(fresh)) || fresh.isEmpty()
                        || (Integer) call(fresh.get(0), "getWindowId") != windowId) throw new IllegalStateException();
                click(find(fresh, "com.android.systemui:id/key" + digit));
            }
            fresh = current();
            if (!expected.equals(target(fresh))) throw new IllegalStateException();
            click(find(fresh, "com.android.systemui:id/key_enter"));
        } else {
            String resource = expected.equals("systemui-credential")
                    ? "com.android.systemui:id/lockPassword" : "com.android.settings:id/password_entry";
            Object field = find(fresh, resource);
            Object bundle = bundleClass.getConstructor().newInstance();
            bundleClass.getMethod("putCharSequence", String.class, CharSequence.class)
                    .invoke(bundle, "ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE", pin);
            if (!(Boolean) nodeClass.getMethod("performAction", int.class, bundleClass)
                    .invoke(field, 2097152, bundle)) throw new IllegalStateException();
            fresh = current();
            if (!expected.equals(target(fresh))) throw new IllegalStateException();
            Object action = Class.forName("android.view.accessibility.AccessibilityNodeInfo$AccessibilityAction")
                    .getField("ACTION_IME_ENTER").get(null);
            int actionId = (Integer) call(action, "getId");
            if (!(Boolean) nodeClass.getMethod("performAction", int.class)
                    .invoke(find(fresh, resource), actionId)) throw new IllegalStateException();
        }
    }

    public static void main(String[] args) {
        try {
            if (args.length == 1 && args[0].equals("--probe")) {
                System.setOut(new java.io.PrintStream(new java.io.FileOutputStream("/data/local/tmp/session-unlock-probe-status")));
            } else {
                System.setOut(new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.out)));
            }
        } catch (Exception error) { System.exit(1); }
        System.setIn(new java.io.FileInputStream(java.io.FileDescriptor.in));
        try {
            Class.forName("android.os.Looper").getMethod("prepareMainLooper").invoke(null);
            Class<?> threadClass = Class.forName("android.os.HandlerThread");
            Object thread = threadClass.getConstructor(String.class).newInstance("SessionUnlock");
            ((Thread) thread).start();
            Object looper = call(thread, "getLooper");
            Class<?> autoClass = Class.forName("android.app.UiAutomation");
            Object connection = Class.forName("android.app.UiAutomationConnection").getConstructor().newInstance();
            Constructor<?> constructor = autoClass.getConstructor(Class.forName("android.os.Looper"),
                    Class.forName("android.app.IUiAutomationConnection"));
            automation = constructor.newInstance(looper, connection);
            int flags = autoClass.getField("FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES").getInt(null);
            autoClass.getMethod("connect", int.class).invoke(automation, flags);
            Object serviceInfo = call(automation, "getServiceInfo");
            Class<?> infoClass = Class.forName("android.accessibilityservice.AccessibilityServiceInfo");
            java.lang.reflect.Field infoFlags = infoClass.getField("flags");
            infoFlags.setInt(serviceInfo, infoFlags.getInt(serviceInfo) | 16); // REPORT_VIEW_IDS
            autoClass.getMethod("setServiceInfo", infoClass).invoke(automation, serviceInfo);
            nodeClass = Class.forName("android.view.accessibility.AccessibilityNodeInfo");
            bundleClass = Class.forName("android.os.Bundle");
            List<Object> current = current();
            String target = target(current);
            if (args.length == 1 && args[0].equals("--watch")) {
                long deadline = System.nanoTime() + 120000000000L;
                while (target.isEmpty() && System.nanoTime() < deadline) {
                    Thread.sleep(500);
                    current = current();
                    target = target(current);
                }
            }
            if (args.length == 1 && args[0].equals("--probe")) {
                System.out.println(target.isEmpty() ? "NO_CREDENTIAL_UI" : "READY " + target);
                // Resource identifiers only: never node text, account names, or entered digits.
                for (Object node : current) {
                    String resource = id(node);
                    if (visible(node) && resource.matches("com\\.android\\.(systemui|settings):id/.*(pin|Pin|password|Password|keyguard|key_enter).*")) {
                        System.out.println("RESOURCE " + resource);
                        if ((Boolean) call(node, "isPassword")) {
                            for (Object action : (List<?>) call(node, "getActionList")) {
                                System.out.println("ACTION " + call(action, "getId"));
                            }
                        }
                    }
                }
            } else if (args.length == 1 && (args[0].equals("--submit") || args[0].equals("--watch")) && !target.isEmpty()) {
                System.out.println("READY " + target);
                System.out.flush();
                // Bound input: do not accept arbitrary-sized stdin or command-line credentials.
                StringBuilder value = new StringBuilder();
                int c;
                while ((c = System.in.read()) != -1 && c != '\n') {
                    if (c < '0' || c > '9' || value.length() >= 16) throw new IllegalArgumentException();
                    value.append((char) c);
                }
                if (value.length() < 4) throw new IllegalArgumentException();
                submit(target, (Integer) call(current.get(0), "getWindowId"), value.toString());
                // Submission is not proof of successful credential verification.
                System.out.println("SUBMITTED_REQUIRES_VERIFICATION");
            } else {
                System.out.println("NO_CREDENTIAL_UI");
                System.exit(2);
            }
            autoClass.getMethod("disconnect").invoke(automation);
            System.exit(0);
        } catch (Throwable error) {
            // Never print an exception, UI dump, or credential-bearing payload.
            System.out.println("ANDROID_HELPER_FAILED");
            System.exit(1);
        }
    }
}
