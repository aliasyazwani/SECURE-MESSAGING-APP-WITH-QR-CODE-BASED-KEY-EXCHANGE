# Firebase Setup Guide for SecureLink

## Step 1 — Create a Firebase Project

1. Go to [https://console.firebase.google.com](https://console.firebase.google.com)
2. Click **"Add project"**
3. Name it `SecureLink` (or any name)
4. Disable Google Analytics (not needed)
5. Click **"Create project"**

---

## Step 2 — Enable Authentication

1. In the Firebase console, click **"Authentication"** in the left sidebar
2. Click **"Get started"**
3. Under **"Sign-in method"**, enable **Email/Password**
4. Click **Save**

---

## Step 3 — Create Cloud Firestore

1. Click **"Firestore Database"** in the left sidebar
2. Click **"Create database"**
3. Choose **"Start in test mode"** (we'll add security rules later)
4. Select your preferred region (e.g., `asia-southeast1` for Malaysia)
5. Click **Done**

---

## Step 4 — Register the Android App

1. On the Firebase project overview page, click the **Android icon**
2. **Android package name:** `com.fyp.secure_link`
3. **App nickname:** `SecureLink Android`
4. **SHA-1 certificate** (optional for now — skip this)
5. Click **"Register app"**
6. Download `google-services.json`
7. Place it at: `android/app/google-services.json`

---

## Step 5 — Install FlutterFire CLI and Configure

Run these commands in your project directory:

```powershell
# Install FlutterFire CLI (once)
dart pub global activate flutterfire_cli

# Configure Firebase (run from project root)
flutterfire configure
```

When prompted:
- Select your Firebase project (`SecureLink`)
- Select **Android** only
- This generates `lib/firebase_options.dart` automatically

> ⚠️ After this, **delete** the placeholder `lib/firebase_options.dart` content
> and use the generated one.

---

## Step 6 — Set Firestore Security Rules

1. In Firebase Console → **Firestore Database** → **Rules** tab
2. Replace the default rules with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Users: any auth user can read, only owner writes
    match /users/{uid} {
      allow read: if request.auth != null;
      allow create: if request.auth.uid == uid;
      allow update, delete: if request.auth.uid == uid;
    }

    // Sessions
    match /sessions/{sessionId} {
      allow create: if request.auth != null
        && request.resource.data.senderUid == request.auth.uid;

      allow read: if request.auth != null
        && (resource.data.senderUid == request.auth.uid
            || resource.data.receiverUid == request.auth.uid
            || resource.data.receiverUid == null);

      allow update: if request.auth != null
        && (resource.data.senderUid == request.auth.uid
            || resource.data.receiverUid == request.auth.uid);

      allow delete: if request.auth != null
        && resource.data.senderUid == request.auth.uid;

      // Messages subcollection
      match /messages/{messageId} {
        allow create: if request.auth != null
          && request.resource.data.senderUid == request.auth.uid;

        allow read: if request.auth != null
          && (get(/databases/$(database)/documents/sessions/$(sessionId)).data.senderUid == request.auth.uid
              || get(/databases/$(database)/documents/sessions/$(sessionId)).data.receiverUid == request.auth.uid);

        allow delete: if request.auth != null
          && (get(/databases/$(database)/documents/sessions/$(sessionId)).data.senderUid == request.auth.uid
              || get(/databases/$(database)/documents/sessions/$(sessionId)).data.receiverUid == request.auth.uid);

        allow update: if false;
      }
    }
  }
}
```

3. Click **"Publish"**

---

## Step 7 — Create Firestore Indexes (if needed)

If you get an index error in the app logs, Firestore will provide a direct link to create
the required composite index. Click it and it will auto-configure.

---

## Step 8 — Run the App

```powershell
# Install dependencies
flutter pub get

# Run on connected Android device or emulator
flutter run
```

---

## Firestore Data Layout (reference)

```
users/
  {uid}/
    uid: string
    email: string
    displayName: string
    createdAt: timestamp

sessions/
  {sessionId}/
    sessionId: string
    senderUid: string
    receiverUid: string | null
    senderEphemeralPublicKey: hex string  ← Curve25519 PUBLIC key only
    receiverEphemeralPublicKey: hex string | null
    status: "pending" | "active" | "ended"
    createdAt: timestamp
    expiresAt: timestamp
    used: boolean

    messages/
      {messageId}/
        messageId: string
        senderUid: string
        ciphertext: hex string   ← AES-256-GCM encrypted, never plaintext
        nonce: hex string        ← random 12-byte IV per message
        mac: hex string          ← GCM authentication tag
        createdAt: timestamp
        expiresAt: timestamp
```

> **Security Note for FYP Viva:**
> Firebase stores ONLY encrypted bytes. Even if an attacker gains Firestore access,
> they cannot read messages without the in-memory session key, which is derived
> locally via X25519 ECDH + HKDF-SHA256 and is never sent to any server.
