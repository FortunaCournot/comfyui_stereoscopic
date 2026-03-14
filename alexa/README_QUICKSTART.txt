Alexa Job Monitor - Quick Start
================================

Goal
----
Get the "job monitor" Alexa custom skill running quickly with your local backend.

1) Backend availability
-----------------------
The backend lifecycle is handled by the daemon script.
Verify health endpoint:
- http://127.0.0.1:5000/health

2) Expose local port 5000 with HTTPS
-------------------------------------
Alexa cannot call private intranet IPs directly.
Use a public HTTPS tunnel (example: ngrok):

- ngrok http 5000

Copy the HTTPS URL, for example:
- https://abc123.ngrok-free.app

3) Configure Alexa Developer Console
------------------------------------
A) Invocation name
- Build -> Invocation
- Set: job monitor
- Save

B) Intent utterances (GetOpenJobsIntent)
- wie viele offene jobs gibt es
- wie viele jobs sind offen
- anzahl offener jobs
- Build Model

C) Endpoint
- Build -> Endpoint
- Set URL: https://<your-tunnel-domain>/alexa
- SSL type: wildcard CA subdomain option
- Save Endpoints

D) Test mode
- Test tab -> Development mode ON

4) Test voice commands
----------------------
- "Alexa, open Job Monitor"
- "How many open jobs are there?"

Expected response:
- "Job Monitor ist bereit."
- "Aktuell gibt es X offene Jobs."

5) Enable proactive push (optional)
-----------------------------------
Create alexa/python/config.json from config.example.json and fill:
- client_id
- client_secret
- refresh_token
- alexa_api_endpoint
- skill_id

Troubleshooting
---------------
- "Alexa doesn't know Job Monitor":
  - Rebuild model, enable Test mode, verify same Amazon account on device + developer console.
- Endpoint fails:
  - Check tunnel is running and endpoint ends with /alexa.
- No proactive push:
  - Check config.json and alexa/script/alexa.log.
