import * as admin from 'firebase-admin';
import fs from 'fs';
import path from 'path';

// =============================================================
// FIREBASE ADMIN INITIALIZATION
// Uses service-account.json (copied from ../service.json)
// =============================================================

let firestoreDb: admin.firestore.Firestore;
let messagingClient: admin.messaging.Messaging;

export function initFirebase(): void {
  const saPath = path.resolve(process.cwd(), 'service-account.json');

  if (!fs.existsSync(saPath)) {
    throw new Error(
      `service-account.json not found at: ${saPath}\n` +
      `Copy it from: c:\\Users\\panda\\OneDrive\\Desktop\\Arion AI\\service.json`
    );
  }

  if (admin.apps.length === 0) {
    const serviceAccount = JSON.parse(fs.readFileSync(saPath, 'utf-8'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount as admin.ServiceAccount),
      projectId: process.env.FIREBASE_PROJECT_ID || 'aegis-crisis-response-493911',
    });
    console.log('✅ [Firebase] Admin SDK initialized');
  }

  firestoreDb    = admin.firestore();
  messagingClient = admin.messaging();
}

export function getFirestore(): admin.firestore.Firestore {
  if (!firestoreDb) throw new Error('Firebase not initialized. Call initFirebase() first.');
  return firestoreDb;
}

export function getMessaging(): admin.messaging.Messaging {
  if (!messagingClient) throw new Error('Firebase not initialized. Call initFirebase() first.');
  return messagingClient;
}

export { admin };
