# Firebase Setup für NutriFlow

## 1. Firebase Projekt erstellen

1. Gehe zu https://console.firebase.google.com
2. Klicke "Projekt hinzufügen"
3. Name: `nutriflow` (oder wie du willst)
4. Google Analytics: optional
5. Klicke "Projekt erstellen"

## 2. App registrieren

### Für iOS:
1. Klicke das iOS-Symbol
2. Bundle ID: `com.nutriflow.app` (oder deine eigene)
3. Lade `GoogleService-Info.plist` herunter

### Für Android:
1. Klicke das Android-Symbol
2. Package Name: `com.nutriflow.app`
3. Lade `google-services.json` herunter

### Für Web (Expo Go):
1. Klicke das Web-Symbol `</>`
2. Name: `NutriFlow Web`
3. Kopiere die Config-Werte

## 3. Firebase Config eintragen

Öffne `src/config/firebase.ts` und ersetze die Platzhalter:

```typescript
const firebaseConfig = {
  apiKey: 'AIzaSy...',           // Aus Firebase Console
  authDomain: 'nutriflow-xxxxx.firebaseapp.com',
  projectId: 'nutriflow-xxxxx',
  storageBucket: 'nutriflow-xxxxx.appspot.com',
  messagingSenderId: '123456789',
  appId: '1:123456789:web:abc...',
};
```

## 4. Authentication aktivieren

1. Firebase Console → Authentication → "Erste Schritte"
2. Sign-in method → "E-Mail/Passwort" → Aktivieren
3. Optional: Google Sign-In aktivieren

## 5. Firestore Datenbank erstellen

1. Firebase Console → Firestore Database → "Datenbank erstellen"
2. Standort: `europe-west3` (Frankfurt) für DSGVO
3. Starte im **Produktionsmodus**

## 6. Sicherheitsregeln

Gehe zu Firestore → Regeln und füge ein:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

Diese Regeln stellen sicher, dass jeder User nur seine eigenen Daten lesen/schreiben kann.

## 7. Fertig!

Die App synchronisiert jetzt automatisch:
- Profil & Ernährungsziele
- Mahlzeiten & Wasser-Log
- Gewichtsverlauf
- Streaks & Badges
- Einstellungen

Alles läuft offline-first: Daten werden lokal gespeichert und im Hintergrund mit Firestore synchronisiert.
