Alexa Job Monitor - End User Setup Guide (Intranet)
===================================================

This guide explains how to make the Alexa Custom Skill "job monitor" usable from your local/intranet environment.

Important
---------
Alexa cloud services cannot directly call private intranet IP addresses.
Even if your backend runs locally, you must expose it via a secure public HTTPS endpoint (for example with ngrok or Cloudflare Tunnel).


1) Prerequisites
----------------
- Amazon account with access to Alexa Developer Console
- Alexa-enabled device (Echo, Alexa app, etc.)
- Running Job Monitor backend on your machine (Flask app)
- Network access from your machine to the internet
- A tunnel tool (recommended: ngrok)


2) Backend availability
-----------------------
The backend lifecycle is handled by the daemon script.
The backend listens on port 5000 by default.

Quick health check in browser:
- http://127.0.0.1:5000/health

You should get JSON like:
- {"status":"ok","open_jobs":0}


3) Expose local backend via HTTPS tunnel
----------------------------------------
Example with ngrok:

- ngrok http 5000

Copy the generated HTTPS URL, for example:
- https://abc123.ngrok-free.app

Your Alexa endpoint URL will be:
- https://abc123.ngrok-free.app/alexa


4) Configure the skill in Alexa Developer Console
--------------------------------------------------
A) Build / Invocation
1. Open your skill in Alexa Developer Console.
2. Go to Build -> Invocation.
3. Set invocation name to:
   - job monitor
4. Save model.

B) Intents / Utterances
1. Ensure GetOpenJobsIntent exists.
2. Add German sample utterances:
   - wie viele offene jobs gibt es
   - wie viele jobs sind offen
   - anzahl offener jobs
3. Save and Build Model.

C) Endpoint
1. Go to Build -> Endpoint.
2. Choose HTTPS endpoint.
3. Set Default Region endpoint to:
   - https://<your-tunnel-domain>/alexa
4. SSL Certificate type:
   - My development endpoint is a sub-domain of a domain that has a wildcard certificate from a certificate authority
5. Save Endpoints.

D) Test mode
1. Go to Test tab.
2. Set Test to Development mode (enabled).


5) Enable skill in Alexa app/device account
--------------------------------------------
Make sure the same Amazon account is used for:
- Alexa Developer Console (skill owner/tester)
- Your Alexa device/app

If needed, enable the skill in Alexa app under Skills (Developer/Test skill).


6) Voice commands to test
-------------------------
- "Alexa, open Job Monitor"
- "How many open jobs are there?"
- German utterance examples also work if configured for de-DE locale.

Expected responses:
- "Job Monitor ist bereit."
- "Aktuell gibt es X offene Jobs."


7) Proactive events configuration
---------------------------------
Create alexa/python/config.json based on config.example.json and fill:
- client_id
- client_secret
- refresh_token
- alexa_api_endpoint
- skill_id

If these are missing/invalid, proactive push will be skipped and logged.
The skill itself can still answer pull requests (voice intents).


8) Typical problems and fixes
-----------------------------
Problem: "Alexa doesn't know Job Monitor"
- Verify invocation name is exactly "job monitor"
- Rebuild interaction model
- Enable test mode
- Confirm account alignment (developer + device)

Problem: Endpoint errors in test
- Verify tunnel URL is alive
- Verify /alexa path is correct
- Verify HTTPS certificate setting in Endpoint

Problem: No proactive notifications
- Verify config.json credentials
- Check alexa/script/alexa.log for proactive_send_failed
- Confirm proactive events permissions are enabled for the skill in developer console

Problem: Old logs are confusing
- alexa.log is truncated on each daemon start


9) Security notes
--------------
- Never publish secrets (client_secret, refresh_token) in public repositories.
- Use least-privilege accounts and rotate credentials when needed.
- Use secure tunnels (HTTPS only).
