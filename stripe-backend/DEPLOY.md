# Deploy Stripe Backend to Google Cloud Run

## Quick Deploy Command

From the `stripe-backend` directory, run:

```bash
# Set your Google Cloud project (replace with your actual project ID)
gcloud config set project YOUR_PROJECT_ID

# Deploy to Cloud Run
gcloud run deploy registry-x-stripe-backend \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars STRIPE_SECRET_KEY=your_stripe_secret_key
```

## Step-by-Step Deployment

### 1. Navigate to backend directory
```bash
cd /Users/federico.joly/Desktop/Dev/stripe-backend
```

### 2. Verify you have the latest code
The `/send-receipt-email` endpoint should be in your `index.js` file at line 207.

### 3. Deploy to Google Cloud Run

**Option A: Using `gcloud run deploy` with source**
```bash
gcloud run deploy registry-x-stripe-backend \
  --source . \
  --region us-central1 \
  --allow-unauthenticated
```

**Option B: Build and deploy with Cloud Build**
```bash
# Submit build to Cloud Build
gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/registry-x-stripe-backend

# Deploy the built image
gcloud run deploy registry-x-stripe-backend \
  --image gcr.io/YOUR_PROJECT_ID/registry-x-stripe-backend \
  --region us-central1 \
  --allow-unauthenticated
```

### 4. Set Environment Variables

After deployment, make sure your Stripe secret key is set:

```bash
gcloud run services update registry-x-stripe-backend \
  --region us-central1 \
  --set-env-vars STRIPE_SECRET_KEY=sk_test_.... 
```

> **Note**: Replace `sk_test_....` with your actual Stripe secret key. Use `sk_test_` for testing or `sk_live_` for production.

### 5. Verify Deployment

Once deployed, test the new endpoint:

```bash
# Get your service URL
gcloud run services describe registry-x-stripe-backend --region us-central1 --format 'value(status.url)'

# Test the health endpoint
curl https://YOUR_SERVICE_URL/health

# The new endpoint will appear as available
```

## Important Notes

- **No Stripe Dashboard Changes Required**: This is purely a backend code deployment
- **Existing Endpoints Preserved**: All your existing endpoints (`/create-payment-intent`, `/create-checkout-session`, etc.) remain unchanged
- **Environment Variables**: Make sure `STRIPE_SECRET_KEY` is set in Cloud Run environment variables
- **Region**: If you originally deployed to a different region, use that same region in all commands

## Troubleshooting

**If you get authentication errors:**
```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

**If you're not sure what service name you used:**
```bash
gcloud run services list
```

**To view current environment variables:**
```bash
gcloud run services describe registry-x-stripe-backend --region us-central1 --format 'value(spec.template.spec.containers[0].env)'
```

## After Deployment

Once deployed successfully, test the receipt feature in your iOS app. The 404 error should be resolved.
