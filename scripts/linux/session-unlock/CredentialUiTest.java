import java.util.ArrayList;
import java.util.List;

/** Run on the host JVM; negative tests for the credential target allowlist. */
public class CredentialUiTest {
    public static class Node {
        String id, pkg;
        boolean password, editable, visible = true;
        Node(String id, String pkg, boolean password, boolean editable) {
            this.id = id; this.pkg = pkg; this.password = password; this.editable = editable;
        }
        public String getViewIdResourceName() { return id; }
        public String getPackageName() { return pkg; }
        public boolean isPassword() { return password; }
        public boolean isEditable() { return editable; }
        public boolean isVisibleToUser() { return visible; }
    }
    static void expect(String result, List<Object> nodes) throws Exception {
        if (!result.equals(CredentialUi.target(nodes))) throw new AssertionError();
    }
    public static void main(String[] args) throws Exception {
        List<Object> nodes = new ArrayList<>();
        Node field = new Node("com.android.systemui:id/lockPassword", "com.android.systemui", true, true);
        nodes.add(field);
        expect("systemui-credential", nodes);
        field.pkg = "untrusted.app";
        expect("", nodes);
        field.pkg = "com.android.systemui";
        field.password = false;
        expect("", nodes);
        field.password = true;
        field.editable = false;
        expect("", nodes);
        field.editable = true;
        field.visible = false;
        expect("", nodes);
        nodes.clear();
        nodes.add(new Node("com.android.systemui:id/pinEntry", "com.android.systemui", true, false));
        nodes.add(new Node("com.android.systemui:id/keyguard_pin_view", "com.android.systemui", false, false));
        nodes.add(new Node("com.android.systemui:id/key_enter", "com.android.systemui", false, false));
        for (int i = 0; i < 9; i++) nodes.add(new Node("com.android.systemui:id/key" + i, "com.android.systemui", false, false));
        expect("", nodes);
        nodes.add(new Node("com.android.systemui:id/key9", "com.android.systemui", false, false));
        expect("keyguard-pin", nodes);
        System.out.println("Passed seven Android credential target checks.");
    }
}
