require('dotenv').config();
const express = require('express');
const cors = require('cors');

const app = express();
const port = process.env.PORT || 8080;

// Configure CORS
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'OPTIONS']
}));
app.use(express.json());

// Configure Resend (only if API key is provided)
const { Resend } = require('resend');
const resend = process.env.RESEND_API_KEY ? new Resend(process.env.RESEND_API_KEY) : null;

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'mailer-service' });
});

// Password recovery email endpoint
app.post('/send-password-reset', async (req, res) => {
    try {
        const { email, resetLink } = req.body;

        // Validate Resend is configured
        if (!resend) {
            return res.status(500).json({
                error: 'Email service not configured. Please set RESEND_API_KEY environment variable.'
            });
        }

        // Validate required fields
        if (!email || !resetLink) {
            return res.status(400).json({ error: 'email and resetLink are required' });
        }

        // Basic email validation
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            return res.status(400).json({ error: 'Invalid email format' });
        }

        // Generate HTML email
        const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
  <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; text-align: center; color: white;">
      <h1 style="margin: 0; font-size: 28px; font-weight: 600;">Password Reset</h1>
      <p style="margin: 10px 0 0 0; font-size: 16px; opacity: 0.9;">Registry X</p>
    </div>
    <div style="padding: 30px;">
      <p style="font-size: 16px; color: #333; line-height: 1.6;">You requested to reset your password. Click the button below to create a new password:</p>
      <div style="text-align: center; margin: 30px 0;">
        <a href="${resetLink}" style="display: inline-block; background-color: #667eea; color: white; padding: 14px 28px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">Reset Password</a>
      </div>
      <p style="font-size: 14px; color: #666; line-height: 1.6;">If you didn't request this, you can safely ignore this email.</p>
      <p style="font-size: 14px; color: #666; line-height: 1.6; margin-top: 20px;">This link will expire in 1 hour.</p>
    </div>
    <div style="padding: 20px; background-color: #f8f9fa; text-align: center; border-top: 1px solid #eee;">
      <p style="margin: 0; font-size: 12px; color: #999;">This email was sent to ${email}</p>
    </div>
  </div>
</body>
</html>
    `;

        // Send email via Resend
        const data = await resend.emails.send({
            from: process.env.PASSREC_MAIL_FROM || 'Registry X <noreply@resend.dev>',
            to: email,
            subject: 'Reset Your Password',
            html: html
        });

        res.json({
            success: true,
            message: 'Password reset email sent successfully',
            recipient: email,
            emailId: data.id
        });
    } catch (error) {
        console.error('Error sending password reset email:', error);
        res.status(500).json({ error: error.message });
    }
});

// Password recovery endpoint (legacy - matches existing iOS app)
app.post('/password-recovery', async (req, res) => {
    try {
        const { email, fullName, temporaryPassword, fromName, fromEmail } = req.body;

        // Validate Resend is configured
        if (!resend) {
            return res.status(500).json({
                error: 'Email service not configured. Please set RESEND_API_KEY environment variable.'
            });
        }

        // Validate required fields
        if (!email || !fullName || !temporaryPassword || !fromName || !fromEmail) {
            return res.status(400).json({ error: 'email, fullName, temporaryPassword, fromName, and fromEmail are required' });
        }

        // Basic email validation
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            return res.status(400).json({ error: 'Invalid email format' });
        }

        // Generate HTML email
        const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
  <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; text-align: center; color: white;">
      <h1 style="margin: 0; font-size: 28px; font-weight: 600;">Password Reset</h1>
      <p style="margin: 10px 0 0 0; font-size: 16px; opacity: 0.9;">Registry X</p>
    </div>
    <div style="padding: 30px;">
      <p style="font-size: 16px; color: #333; line-height: 1.6;">Hello <strong>${fullName}</strong>,</p>
      <p style="font-size: 16px; color: #333; line-height: 1.6;">Your password has been reset. Your new temporary password is:</p>
      <div style="text-align: center; margin: 30px 0;">
        <div style="display: inline-block; background-color: #f8f9fa; padding: 20px 30px; border-radius: 8px; border: 2px dashed #667eea;">
          <code style="font-size: 24px; font-weight: 700; color: #667eea; letter-spacing: 2px;">${temporaryPassword}</code>
        </div>
      </div>
      <p style="font-size: 14px; color: #666; line-height: 1.6;">Please log in with this temporary password and change it immediately in your account settings.</p>
      <p style="font-size: 14px; color: #999; line-height: 1.6; margin-top: 20px;">If you didn't request this password reset, please contact support immediately.</p>
    </div>
    <div style="padding: 20px; background-color: #f8f9fa; text-align: center; border-top: 1px solid #eee;">
      <p style="margin: 0; font-size: 12px; color: #999;">This email was sent to ${email}</p>
    </div>
  </div>
</body>
</html>
    `;

        // Send email via Resend
        const data = await resend.emails.send({
            from: `${fromName} <${fromEmail}>`,
            to: email,
            subject: 'Your Password Has Been Reset',
            html: html
        });

        res.json({
            success: true,
            message: 'Password recovery email sent successfully',
            recipient: email,
            emailId: data.id
        });
    } catch (error) {
        console.error('Error sending password recovery email:', error);
        res.status(500).json({ error: error.message });
    }
});

// Receipt email endpoint
app.post('/send-receipt', async (req, res) => {
    try {
        const { email, subject, html, fromName, fromEmail } = req.body;

        // Validate Resend is configured
        if (!resend) {
            return res.status(500).json({
                error: 'Email service not configured. Please set RESEND_API_KEY environment variable.'
            });
        }

        // Validate required fields
        if (!email || !subject || !html || !fromName || !fromEmail) {
            return res.status(400).json({ error: 'email, subject, html, fromName, and fromEmail are required' });
        }

        // Basic email validation
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            return res.status(400).json({ error: 'Invalid email format' });
        }

        // Send email via Resend
        const data = await resend.emails.send({
            from: `${fromName} <${fromEmail}>`,
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

app.listen(port, () => {
    console.log(`Mailer service listening on port ${port}`);
    console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});
