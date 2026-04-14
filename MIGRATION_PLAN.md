# Supabase Cloud Migration Plan

## Overview
NTSApp features a production-ready, offline-first synchronization engine. It is architected to be platform-agnostic, using a combination of local SQLite storage and a sophisticated Supabase/Backblaze B2 backend.

## Current Architecture
- **Local Database**: SQLite for high-performance offline access.
- **Cloud Sync**: 17 Supabase Edge Functions (Deno) handling conflict resolution, batching, and device synchronization.
- **Media Archiving**: 
  - **Local**: On-device file system caching.
  - **Thumbnails**: Supabase Storage for fast CDN-backed previews.
  - **Large Media**: Integrated with **Backblaze B2** (via S3-compatible API) for cost-effective, infinite storage.
- **Security**: Client-side encryption (AES-GCM) of sensitive data and thumbnails before they leave the device.
- **State Management**: Event-driven architecture using `EventStream` to keep UI in sync across different pages.

## High-Level Migration Steps

### 1. Infrastructure Initialization
- **Supabase**: Create a new project. You will need the **Project URL** and **Anon Key**.
- **Backblaze B2**: Create a bucket and application keys if you intend to use the built-in media archiving logic.
- **FCM (Firebase Cloud Messaging)**: Setup a project for push-to-sync notifications.

### 2. Database & Storage Setup
- **Schema**: Recreate the database structure. Tables found: `plans`, `storage`, `devices`, `files`, `thmbs`, `item`, `itemgroup`, `category`, `categorygroup`.
- **RLS**: Enable Row Level Security on all tables to ensure users can only ever see their own data.
- **Buckets**: Create the `thmbs` and `files` buckets in Supabase Storage.

### 3. Edge Function Deployment
Using the Supabase CLI, deploy the functions in `supabase/functions/`:
- The core sync logic is handled by `push_changes` and `fetch_changes`.
- File management is handled by the `get_upload_url` and `finish_parts_upload` suite.
- *Note: You must configure environment secrets (B2 keys, etc.) in Supabase for these to run.*

### 4. Client-Side Update
The app is modular and retrieves its credentials at build-time. To switch backends, simply build/run with new flags:
```bash
flutter run --dart-define=SUPABASE_URL=YOUR_NEW_URL --dart-define=SUPABASE_KEY=YOUR_NEW_ANON_KEY
```

## Security Recommendations
- **Maintain Encryption**: Do not disable the existing encryption logic in `CryptoUtils`. It provides the "Zero-Knowledge" privacy that makes this app a true "Note Safe."
- **Audit RLS**: Always verify that `user_id` checks are active in Supabase policies.

---
*Documented by Antigravity AI Coding Assistant*
