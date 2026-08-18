// File generated for 札幌中野冷機 日報アプリ (project: sn-report)
// This file allows multi-platform Firebase initialization.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDiHbvFqE4OhyZFoWjaYm4s8ANsaieMZ6o',
    appId: '1:924627646300:web:795f6e2bbc0dcebc943399',
    messagingSenderId: '924627646300',
    projectId: 'sn-report',
    authDomain: 'sn-report.firebaseapp.com',
    storageBucket: 'sn-report.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAYFHqFn38F5qOCAbOBghkh207NT2-itzA',
    appId: '1:924627646300:android:e58c46a5c18572c9943399',
    messagingSenderId: '924627646300',
    projectId: 'sn-report',
    storageBucket: 'sn-report.firebasestorage.app',
  );
}
