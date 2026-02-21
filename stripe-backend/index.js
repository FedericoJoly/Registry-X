const express = require('express');
const cors = require('cors');
const Stripe = require('stripe');
const app = express();
const port = process.env.PORT || 8080;
// Initialize Stripe with secret key from environment
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
// Middleware
app.use(cors({
  origin: '*', // Adjust in production for security
  methods: ['GET', 'POST'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json());

// Configure Resend for receipt emails (only if API key is provided)
const { Resend } = require('resend');
const resend = process.env.RESEND_API_KEY ? new Resend(process.env.RESEND_API_KEY) : null;

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Terminal connection token for SDK authentication
app.post('/connection-token', async (req, res) => {
  try {
    const connectionToken = await stripe.terminal.connectionTokens.create();
    res.json({ secret: connectionToken.secret });
  } catch (error) {
    console.error('Error creating connection token:', error);
    res.status(500).json({ error: error.message });
  }
});

// Create Payment Intent for Tap to Pay
app.post('/create-payment-intent', async (req, res) => {
  try {
    const { amount, currency, description, lineItems, metadata } = req.body;
    // Validate required fields
    if (!amount || !currency) {
      return res.status(400).json({ error: 'amount and currency are required' });
    }

    // Build enhanced description with line items
    let enhancedDescription = description || 'Registry_X Transaction';
    let enhancedMetadata = { ...(metadata || {}) };

    if (lineItems && Array.isArray(lineItems) && lineItems.length > 0) {
      // Create itemized description
      const itemsList = lineItems.map(item =>
        `${item.quantity}x ${item.name} (${item.price})`
      ).join(', ');

      enhancedDescription = `${description || 'Order'} | Items: ${itemsList}`;

      // Store line items in metadata (each item separately to respect Stripe limits)
      lineItems.forEach((item, index) => {
        enhancedMetadata[`item_${index}_name`] = item.name;
        enhancedMetadata[`item_${index}_qty`] = String(item.quantity);
        enhancedMetadata[`item_${index}_price`] = String(item.price);
      });
      enhancedMetadata['items_count'] = String(lineItems.length);
    }

    // Create payment intent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(amount * 100), // Convert to cents
      currency: currency.toLowerCase(),
      description: enhancedDescription,
      statement_descriptor: description ? description.substring(0, 22) : 'Registry_X', // Max 22 chars for card statements
      metadata: enhancedMetadata,
      payment_method_types: ['card'], // For online card payments
      capture_method: 'automatic'
    });
    res.json({
      clientSecret: paymentIntent.client_secret,
      intentId: paymentIntent.id,
      amount: paymentIntent.amount,
      currency: paymentIntent.currency
    });
  } catch (error) {
    console.error('Error creating payment intent:', error);
    res.status(500).json({ error: error.message });
  }
});

// Create Terminal Payment Intent for Tap to Pay on iPhone
app.post('/create-terminal-payment-intent', async (req, res) => {
  try {
    const { amount, currency, description, metadata } = req.body;
    // Validate required fields
    if (!amount || !currency) {
      return res.status(400).json({ error: 'amount and currency are required' });
    }
    // Create payment intent for Terminal
    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(amount * 100), // Convert to cents
      currency: currency.toLowerCase(),
      description: description || 'Registry_X Transaction',
      statement_descriptor: description ? description.substring(0, 22) : 'Registry_X',
      metadata: metadata || {},
      payment_method_types: ['card_present'], // For Terminal readers
      capture_method: 'automatic'
    });
    res.json({
      clientSecret: paymentIntent.client_secret,
      intentId: paymentIntent.id,
      amount: paymentIntent.amount,
      currency: paymentIntent.currency
    });
  } catch (error) {
    console.error('Error creating terminal payment intent:', error);
    res.status(500).json({ error: error.message });
  }
});

// Create Checkout Session for QR Code payments
app.post('/create-checkout-session', async (req, res) => {
  try {
    const { amount, currency, description, companyName, lineItems, metadata, successUrl, cancelUrl } = req.body;
    // Validate required fields
    if (!amount || !currency) {
      return res.status(400).json({ error: 'amount and currency are required' });
    }

    // Build line items - use provided line items or fall back to single item
    let sessionLineItems;
    if (lineItems && Array.isArray(lineItems) && lineItems.length > 0) {
      sessionLineItems = lineItems.map(item => ({
        price_data: {
          currency: currency.toLowerCase(),
          product_data: {
            name: item.name,
          },
          unit_amount: Math.round(item.price * 100), // Convert to cents
        },
        quantity: item.quantity || 1,
      }));
    } else {
      // Fallback to single line item
      sessionLineItems = [{
        price_data: {
          currency: currency.toLowerCase(),
          product_data: {
            name: description || 'Registry_X Purchase',
          },
          unit_amount: Math.round(amount * 100), // Convert to cents
        },
        quantity: 1,
      }];
    }

    // Create session config with payment intent data
    const sessionConfig = {
      payment_method_types: ['card'],
      line_items: sessionLineItems,
      mode: 'payment',
      success_url: successUrl || `${req.headers.origin}/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: cancelUrl || `${req.headers.origin}/cancel`,
      metadata: metadata || {},
      payment_intent_data: {
        description: description || 'Registry_X Transaction',
        statement_descriptor: companyName ? companyName.substring(0, 22) : (description ? description.substring(0, 22) : 'Registry_X'),
      }
    };

    // Create checkout session
    const session = await stripe.checkout.sessions.create(sessionConfig);
    res.json({
      sessionId: session.id,
      url: session.url // QR code will point to this URL
    });
  } catch (error) {
    console.error('Error creating checkout session:', error);
    res.status(500).json({ error: error.message });
  }
});
// Verify Payment Intent status
app.get('/payment-intent/:id', async (req, res) => {
  try {
    // Expand latest_charge to get payment_method_details.card_present.last4 (TTP)
    const paymentIntent = await stripe.paymentIntents.retrieve(req.params.id, {
      expand: ['latest_charge']
    });
    // Extract last4 from charge: card_present for TTP, card for online payments
    const details = paymentIntent.latest_charge?.payment_method_details;
    const last4 = details?.card_present?.last4 || details?.card?.last4 || null;
    res.json({
      status: paymentIntent.status,
      amount: paymentIntent.amount,
      currency: paymentIntent.currency,
      metadata: paymentIntent.metadata,
      last4: last4
    });
  } catch (error) {
    console.error('Error retrieving payment intent:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get checkout session status
app.get('/checkout-session/:sessionId', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const session = await stripe.checkout.sessions.retrieve(sessionId);

    res.json({
      status: session.payment_status, // 'paid', 'unpaid', 'no_payment_required'
      amount: session.amount_total,
      currency: session.currency
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Send custom receipt email for manual payments (Cash, Bizum, Transfer)
app.post('/send-receipt', async (req, res) => {
  try {
    const { email, subject, html } = req.body;

    // Validate Resend is configured
    if (!resend) {
      return res.status(500).json({
        error: 'Email service not configured. Please set RESEND_API_KEY environment variable.'
      });
    }

    // Validate required fields
    if (!email || !subject || !html) {
      return res.status(400).json({ error: 'email, subject, and html are required' });
    }

    // Basic email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ error: 'Invalid email format' });
    }

    // Send email via Resend
    const data = await resend.emails.send({
      from: process.env.EMAIL_FROM || 'Registry X <noreply@resend.dev>',
      to: email,
      subject: subject,
      html: html
    });

    res.json({
      success: true,
      message: 'Receipt email sent successfully',
      recipient: email,
      emailId: data.id
    });
  } catch (error) {
    console.error('Error sending custom receipt email:', error);
    res.status(500).json({ error: error.message });
  }
});

// Send receipt email for tap-to-pay transactions
app.post('/send-receipt-email', async (req, res) => {
  try {
    const { paymentIntentId, email } = req.body;

    // Validate required fields
    if (!paymentIntentId || !email) {
      return res.status(400).json({ error: 'paymentIntentId and email are required' });
    }

    // Basic email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ error: 'Invalid email format' });
    }

    // Retrieve the payment intent to get the charge ID
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);

    // Check if payment was successful
    if (paymentIntent.status !== 'succeeded') {
      return res.status(400).json({
        error: `Payment has not succeeded. Current status: ${paymentIntent.status}`
      });
    }

    // Get the charge ID from the payment intent
    const chargeId = paymentIntent.latest_charge;

    if (!chargeId) {
      return res.status(400).json({ error: 'No charge found for this payment intent' });
    }

    // Update the charge with the receipt email
    // Stripe automatically sends the receipt when this field is updated
    const charge = await stripe.charges.update(chargeId, {
      receipt_email: email
    });

    res.json({
      success: true,
      chargeId: charge.id,
      receiptEmail: charge.receipt_email,
      message: 'Receipt email sent successfully'
    });
  } catch (error) {
    console.error('Error sending receipt email:', error);
    res.status(500).json({ error: error.message });
  }
});

// Refund a payment intent — used by the split payment void flow
// when a later card fails and previously captured intents must be unwound
app.post('/refund-payment-intent', async (req, res) => {
  try {
    const { paymentIntentId } = req.body;

    if (!paymentIntentId) {
      return res.status(400).json({ error: 'paymentIntentId is required' });
    }

    const refund = await stripe.refunds.create({
      payment_intent: paymentIntentId,
    });

    console.log(`Refund created for intent ${paymentIntentId}: ${refund.id} (${refund.status})`);

    res.json({
      success: true,
      refundId: refund.id,
      status: refund.status,
      amount: refund.amount,
      currency: refund.currency,
    });
  } catch (error) {
    console.error('Error creating refund:', error);
    res.status(500).json({ error: error.message });
  }
});

// Webhook endpoint for Stripe events (optional but recommended)
app.post('/webhook', express.raw({ type: 'application/json' }), async (req, res) => {
  const sig = req.headers['stripe-signature'];
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!webhookSecret) {
    return res.status(400).send('Webhook secret not configured');
  }
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, webhookSecret);
  } catch (err) {
    console.error('Webhook signature verification failed:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }
  // Handle the event
  switch (event.type) {
    case 'payment_intent.succeeded':
      const paymentIntent = event.data.object;
      console.log('PaymentIntent succeeded:', paymentIntent.id);
      // Add your business logic here (e.g., update database)
      break;
    case 'payment_intent.payment_failed':
      console.log('PaymentIntent failed:', event.data.object.id);
      break;
    default:
      console.log(`Unhandled event type ${event.type}`);
  }
  res.json({ received: true });
});
// Success and cancel pages for Stripe checkout
app.get('/success', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Payment Successful</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; text-align: center; padding: 50px; background: #f5f5f5; }
        .container { background: white; border-radius: 10px; padding: 40px; max-width: 400px; margin: 0 auto; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #4CAF50; }
        .checkmark { font-size: 80px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="checkmark">✓</div>
        <h1>Payment Successful!</h1>
        <p>Your payment has been processed successfully.</p>
        <p style="color: #666; font-size: 14px;">You can close this window and return to the app.</p>
      </div>
    </body>
    </html>
  `);
});
app.get('/cancel', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Payment Cancelled</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; text-align: center; padding: 50px; background: #f5f5f5; }
        .container { background: white; border-radius: 10px; padding: 40px; max-width: 400px; margin: 0 auto; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #ff9800; }
        .icon { font-size: 80px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="icon">⚠️</div>
        <h1>Payment Cancelled</h1>
        <p>Your payment was cancelled.</p>
        <p style="color: #666; font-size: 14px;">You can close this window and return to the app.</p>
      </div>
    </body>
    </html>
  `);
});
// Start server
app.listen(port, () => {
  console.log(`Stripe backend listening on port ${port}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});