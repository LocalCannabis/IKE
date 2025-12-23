# LocalBot Upstock API Documentation
**For Android Tablet App Integration**

Version: 1.0  
Last Updated: December 23, 2025  
Base URL: `https://app.localcannabisco.ca` (Production)  
Base URL: `http://localhost:5000` (Development)

---

## Table of Contents
1. [Authentication](#authentication)
2. [API Endpoints](#api-endpoints)
3. [Data Models](#data-models)
4. [Error Handling](#error-handling)
5. [Workflow Examples](#workflow-examples)
6. [Testing](#testing)

---

## Authentication

All upstock endpoints require JWT authentication via Google OAuth.

### Step 1: Obtain Google ID Token
Use Google Sign-In on Android to get an ID token for the user.

```kotlin
// Android example (using Google Sign-In SDK)
val account = GoogleSignIn.getLastSignedInAccount(context)
val idToken = account?.idToken
```

### Step 2: Exchange for LocalBot JWT
```http
POST /api/auth/google
Content-Type: application/json

{
  "token": "google_id_token_here"
}
```

**Response:**
```json
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "user": {
    "id": "user@localcannabisco.ca",
    "email": "user@localcannabisco.ca",
    "name": "Tim Smith",
    "role": "admin"
  }
}
```

### Step 3: Use JWT in Subsequent Requests
Include the JWT in the Authorization header:

```http
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGc...
```

**Token Expiry:** JWTs expire after 24 hours. Handle 401 responses by re-authenticating.

---

## API Endpoints

### 1. Start Upstock Run

**POST** `/api/upstock/runs/start`

Creates a new upstock run and computes the pull list based on sales since the last completed run.

**Request:**
```json
{
  "store_id": 1,
  "location_id": "FOH_DISPLAY",
  "window_end_at": "2025-12-23T22:00:00Z",  // optional
  "notes": "End of day upstock"  // optional
}
```

**Response:** `201 Created`
```json
{
  "run": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "store_id": 1,
    "location_id": "FOH_DISPLAY",
    "window_start_at": "2025-12-22T22:00:00Z",
    "window_end_at": "2025-12-23T22:00:00Z",
    "status": "in_progress",
    "created_by_user_id": "user@localcannabisco.ca",
    "created_at": "2025-12-23T22:05:00Z",
    "completed_at": null,
    "notes": "End of day upstock",
    "lines": [
      {
        "id": "line-uuid",
        "run_id": "550e8400-e29b-41d4-a716-446655440000",
        "sku": "1234567",
        "product_name": "BLUE DREAM PRE-ROLL 5X0.5G",
        "brand": "Good Supply",
        "category": "Pre-Rolls",
        "subcategory": "Sativa",
        "cabinet": "Pre-Rolls",
        "item_size": "2.5g",
        "sold_qty": 5,
        "suggested_pull_qty": 5,
        "pulled_qty": null,
        "status": "pending",
        "boh_qty": 20,
        "exception_reason": null,
        "updated_at": "2025-12-23T22:05:00Z",
        "updated_by_user_id": null
      }
      // ... more lines
    ]
  },
  "stats": {
    "total": 45,
    "done": 0,
    "pending": 45,
    "skipped": 0,
    "exceptions": 0,
    "completion_rate": 0.0
  }
}
```

---

### 2. Get Upstock Runs

**GET** `/api/upstock/runs?store_id=1&location_id=FOH_DISPLAY&status=in_progress&limit=50`

Retrieve upstock runs with optional filters.

**Query Parameters:**
- `store_id` (required): Store ID
- `location_id` (optional): Filter by location
- `status` (optional): `in_progress`, `completed`, or `abandoned`
- `limit` (optional): Max results (default: 50)

**Response:** `200 OK`
```json
{
  "runs": [
    {
      "id": "uuid",
      "store_id": 1,
      "location_id": "FOH_DISPLAY",
      "window_start_at": "2025-12-22T22:00:00Z",
      "window_end_at": "2025-12-23T22:00:00Z",
      "status": "completed",
      "created_by_user_id": "user@localcannabisco.ca",
      "created_at": "2025-12-23T22:05:00Z",
      "completed_at": "2025-12-23T23:15:00Z",
      "notes": null
    }
  ],
  "count": 1
}
```

---

### 3. Get Run Detail

**GET** `/api/upstock/runs/{run_id}`

Get detailed run with all lines.

**Response:** `200 OK`
```json
{
  "run": {
    "id": "uuid",
    "lines": [ /* array of line objects */ ]
  },
  "stats": {
    "total": 45,
    "done": 40,
    "pending": 2,
    "skipped": 2,
    "exceptions": 1,
    "completion_rate": 88.9
  }
}
```

---

### 4. Update Run Line

**PATCH** `/api/upstock/runs/{run_id}/lines/{sku}`

Update a line with pulled quantity and status.

**Request:**
```json
{
  "pulled_qty": 5,
  "status": "done"  // "done" | "skipped" | "exception"
}
```

**For Exceptions:**
```json
{
  "pulled_qty": 0,
  "status": "exception",
  "exception_reason": "BOH short - only had 3 units"
}
```

**Response:** `200 OK`
```json
{
  "line": {
    "id": "line-uuid",
    "sku": "1234567",
    "pulled_qty": 5,
    "status": "done",
    "updated_at": "2025-12-23T22:30:00Z",
    "updated_by_user_id": "user@localcannabisco.ca"
  }
}
```

---

### 5. Complete Run

**POST** `/api/upstock/runs/{run_id}/complete`

Mark run as completed.

**Request (optional):**
```json
{
  "validate_all_resolved": false
}
```

If `validate_all_resolved` is true, the API will return an error if any lines are still pending.

**Response:** `200 OK`
```json
{
  "run": {
    "id": "uuid",
    "status": "completed",
    "completed_at": "2025-12-23T23:15:00Z"
  },
  "stats": {
    "total": 45,
    "done": 42,
    "skipped": 2,
    "exceptions": 1,
    "pending": 0,
    "completion_rate": 93.3
  }
}
```

---

### 6. Abandon Run

**POST** `/api/upstock/runs/{run_id}/abandon`

Mark run as abandoned (e.g., staff shortage, emergency).

**Request:**
```json
{
  "reason": "Staff shortage - closing early"
}
```

**Response:** `200 OK`
```json
{
  "run": {
    "id": "uuid",
    "status": "abandoned",
    "notes": "End of day upstock\nAbandoned: Staff shortage - closing early"
  }
}
```

---

### 7. Get Baselines (Par Levels)

**GET** `/api/upstock/baselines?store_id=1&location_id=FOH_DISPLAY`

Retrieve par level baselines for a store/location.

**Response:** `200 OK`
```json
{
  "baselines": [
    {
      "id": 1,
      "store_id": 1,
      "location_id": "FOH_DISPLAY",
      "sku": "1234567",
      "par_qty": 10,
      "cabinet": "Pre-Rolls",
      "subcategory": "Sativa",
      "updated_at": "2025-12-20T10:00:00Z",
      "updated_by_user_id": "admin@localcannabisco.ca"
    }
  ],
  "count": 150
}
```

---

### 8. Update Baselines

**PUT** `/api/upstock/baselines`

Bulk create or update baselines.

**Request:**
```json
{
  "store_id": 1,
  "location_id": "FOH_DISPLAY",
  "baselines": [
    {
      "sku": "1234567",
      "par_qty": 10,
      "cabinet": "Pre-Rolls",
      "subcategory": "Sativa"
    }
  ]
}
```

**Response:** `200 OK`
```json
{
  "message": "Updated 5 and created 10 baselines",
  "created": 10,
  "updated": 5
}
```

---

### 9. Trigger CSV Import (Manual)

**POST** `/api/upstock/imports/process`

Manually trigger email processing for CSV imports (useful for testing).

**Request:**
```json
{
  "store_id": 1,
  "days_back": 2
}
```

**Response:** `200 OK`
```json
{
  "processed_count": 2,
  "failed_count": 0,
  "imports": [
    {
      "id": "uuid",
      "store_id": 1,
      "import_type": "itemized_sales",
      "received_at": "2025-12-23T21:30:00Z",
      "processed_at": "2025-12-23T22:00:00Z",
      "status": "processed",
      "rows_processed": 234
    }
  ]
}
```

---

## Data Models

### UpstockRun
```typescript
{
  id: string;              // UUID
  store_id: number;
  location_id: string;     // e.g., "FOH_DISPLAY"
  window_start_at: string; // ISO 8601 datetime
  window_end_at: string;
  status: "in_progress" | "completed" | "abandoned";
  created_by_user_id: string;
  created_at: string;
  completed_at: string | null;
  notes: string | null;
}
```

### UpstockRunLine
```typescript
{
  id: string;
  run_id: string;
  sku: string;
  product_name: string;
  brand: string;
  category: string;
  subcategory: string;
  cabinet: string;
  item_size: string;
  sold_qty: number;         // Units sold in window
  suggested_pull_qty: number; // Suggested units to pull
  pulled_qty: number | null;  // Actual units pulled
  status: "pending" | "done" | "skipped" | "exception";
  boh_qty: number | null;   // Back-of-house available qty
  exception_reason: string | null;
  updated_at: string;
  updated_by_user_id: string | null;
}
```

---

## Error Handling

### HTTP Status Codes
- `200 OK`: Success
- `201 Created`: Resource created
- `400 Bad Request`: Invalid input
- `401 Unauthorized`: Missing or invalid JWT
- `404 Not Found`: Resource not found
- `500 Internal Server Error`: Server error

### Error Response Format
```json
{
  "error": "Detailed error message"
}
```

### Common Errors

**401 Unauthorized**
```json
{
  "msg": "Token has expired"
}
```
**Solution:** Re-authenticate with Google OAuth and obtain a new JWT.

**400 Bad Request**
```json
{
  "error": "store_id is required"
}
```
**Solution:** Ensure all required fields are present in request body.

**404 Not Found**
```json
{
  "error": "Run not found"
}
```
**Solution:** Verify the run_id exists.

---

## Workflow Examples

### Complete Upstock Flow (Android)

```kotlin
// 1. User taps "START UPSTOCK"
val startRequest = UpstockStartRequest(
    storeId = 1,
    locationId = "FOH_DISPLAY",
    notes = "End of day upstock"
)

val response = api.startUpstockRun(jwtToken, startRequest)
val run = response.run

// 2. Display checklist grouped by cabinet
val groupedLines = run.lines.groupBy { it.cabinet }

groupedLines.forEach { (cabinet, lines) ->
    // Render cabinet header
    renderCabinetHeader(cabinet)
    
    lines.forEach { line ->
        // Render line item with quick actions
        renderLineItem(line)
    }
}

// 3. User marks line as done
fun onLineDone(line: UpstockRunLine, pulledQty: Int) {
    val updateRequest = LineUpdateRequest(
        pulledQty = pulledQty,
        status = "done"
    )
    
    api.updateRunLine(jwtToken, run.id, line.sku, updateRequest)
}

// 4. User marks line as exception
fun onLineException(line: UpstockRunLine, reason: String) {
    val updateRequest = LineUpdateRequest(
        pulledQty = 0,
        status = "exception",
        exceptionReason = reason
    )
    
    api.updateRunLine(jwtToken, run.id, line.sku, updateRequest)
}

// 5. User completes run
fun onCompleteRun() {
    val completeRequest = CompleteRunRequest(
        validateAllResolved = false
    )
    
    val result = api.completeRun(jwtToken, run.id, completeRequest)
    
    // Show summary
    showCompletionSummary(result.stats)
}
```

### Scanner Integration

```kotlin
// On barcode scan
fun onBarcodeScanned(barcode: String) {
    // Find matching line by SKU
    val matchingLine = run.lines.find { it.sku == barcode }
    
    if (matchingLine != null) {
        // Scroll to and highlight the line
        scrollToLine(matchingLine)
        highlightLine(matchingLine)
        
        // Show quick confirm dialog
        showQuickConfirmDialog(matchingLine)
    } else {
        showError("Product not in upstock list")
    }
}
```

---

## Testing

### Development Environment
Base URL: `http://localhost:5000` or `http://192.168.x.x:5000` (your dev machine IP)

### Test Credentials
Use your Google account with `@localcannabisco.ca` domain.

### Postman Collection
Import the provided Postman collection for API testing:
- Download: `/docs/LocalBot_Upstock_API.postman_collection.json`

### Sample Data
Create test data with:
```bash
# On the backend server
cd /home/macklemoron/Projects/JFK/backend
source .venv/bin/activate
python scripts/seed_upstock_test_data.py
```

---

## Support

For API issues or questions:
- Email: tim@localcannabisco.ca
- Slack: #localbot-dev

---

**END OF DOCUMENTATION**
