#!/bin/sh
#Copyright (C) The openNDS Contributors 2004-2022
#Copyright (C) BlueWave Projects and Services 2015-2023
#This software is released under the GNU GPL license.
#
# Custom TOS captive portal theme for Ahmed homelab guest WiFi
# Design matches enrol.home.aahmed.ca aesthetic
#

title="theme_ahmed_tos"

generate_splash_sequence() {
	click_to_continue
}

header() {
	gatewayurl=$(printf "${gatewayurl//%/\\x}")
	if [ "$client_type" = "cpd_can" ]; then
		echo "<!DOCTYPE html><html><head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
<title>Guest WiFi</title>
</head><body style=\"background:#ffffff;color:#111111;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;padding:16px;\">"
		return
	fi
	echo "<!DOCTYPE html><html><head>
<meta http-equiv=\"Cache-Control\" content=\"no-cache, no-store, must-revalidate\">
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
<title>Guest WiFi</title>
<style>
body{margin:0;padding:16px;background:#ffffff;color:#111111;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:16px;line-height:1.4}
.c{max-width:520px;margin:0 auto;padding:16px;border:1px solid #d9d9d9;border-radius:10px;background:#fff}
.ic{font-size:22px;margin-bottom:10px}
h1{font-size:22px;line-height:1.2;margin:0 0 6px 0;color:#111}
.sub{font-size:14px;color:#333;margin:0 0 12px 0}
.tb{border:1px solid #d9d9d9;border-radius:8px;padding:10px;margin:0 0 12px 0;background:#fafafa;color:#222;max-height:220px;overflow:auto}
.tb h3{font-size:14px;margin:8px 0 4px 0}
.tb h3:first-child{margin-top:0}
.tb ul{margin:4px 0 8px 20px;padding:0}
.btn{display:block;width:100%;padding:12px;border:1px solid #0a7f45;border-radius:8px;background:#0a7f45;color:#fff;font-size:16px;font-weight:700}
.btn2{background:#fff;color:#0a7f45}
.ft{text-align:center;margin-top:10px;font-size:12px;color:#666}
.ok h1{color:#0a7f45}
.err h1{color:#b00020}
</style></head><body><div class=\"c\">"
}

footer() {
	if [ "$client_type" = "cpd_can" ]; then
		echo "</body></html>"
		exit 0
	fi
	echo "<div class=\"ft\">ahmed.ca network &middot; 24h session</div></div></body></html>"
	exit 0
}

click_to_continue() {
	if [ "$continue" = "clicked" ]; then
		thankyou_page
		footer
	fi
	continue_form
	footer
}

continue_form() {
	if [ "$client_type" = "cpd_can" ]; then
		echo "<h1>Ahmed Guest WiFi</h1>
<p>Tap Agree to connect to the internet.</p>
<form action=\"/opennds_preauth/\" method=\"get\">
<input type=\"hidden\" name=\"fas\" value=\"$fas\">
<input type=\"hidden\" name=\"continue\" value=\"clicked\">
<input type=\"submit\" value=\"Agree &amp; Connect\" class=\"btn\">
</form>"
		return
	fi

	echo "<div class=\"ic\">&#x1F6E1;</div>
<h1>Ahmed Guest WiFi</h1>
<p class=\"sub\">Review and accept the terms below to get online.</p>
<div class=\"tb\">
<h3>Acceptable Use</h3>
<ul>
<li>This is a private guest network providing internet-only access.</li>
<li>No access to internal network resources, servers, or devices.</li>
<li>No illegal activity, network scanning, or excessive bandwidth abuse.</li>
</ul>
<h3>Privacy</h3>
<ul>
<li>Device MAC, IP, and connection timestamps are logged for security.</li>
<li>DNS is filtered via AdGuard (malware + ad blocking).</li>
<li>Logs retained 30 days, not shared with third parties.</li>
</ul>
<h3>Limits</h3>
<ul>
<li>Sessions expire after 24 hours &mdash; reconnect to renew.</li>
<li>Service provided as-is, may be terminated without notice.</li>
</ul>
</div>
<form action=\"/opennds_preauth/\" method=\"get\">
<input type=\"hidden\" name=\"fas\" value=\"$fas\">
<input type=\"hidden\" name=\"continue\" value=\"clicked\">
<input type=\"submit\" value=\"Accept &amp; Connect\" class=\"btn\">
</form>"
}

landing_page() {
	originurl=$(printf "${originurl//%/\\x}")
	gatewayurl=$(printf "${gatewayurl//%/\\x}")

	configure_log_location
	. $mountpoint/ndscids/ndsinfo

	auth_log

	if [ "$ndsstatus" = "authenticated" ]; then
		echo "<div class=\"ok\">
<div class=\"ic\">&#x2705;</div>
<h1>Session Status</h1>
<p><strong>$gatewayname</strong><br>Portal Version: $version</p>
<p>Internet access is active. Tap Continue to open the session page.</p>
</div>
<form action=\"http://neverssl.com\" method=\"get\">
<input type=\"submit\" value=\"Continue Browsing\" class=\"btn btn2\">
</form>"
	else
		echo "<div class=\"err\">
<div class=\"ic\">&#x274C;</div>
<h1>Connection Failed</h1>
<p>Unable to authenticate. Please reconnect to the WiFi and try again.</p></div>"
	fi

	footer
}

thankyou_page() {
	if [ -z "$custom" ]; then
		customhtml=""
	else
		customhtml="<input type=\"hidden\" name=\"custom\" value=\"$custom\">"
	fi

	if [ "$client_type" = "cpd_can" ]; then
		echo "<h1>Connecting...</h1>
<p>Tap Continue to finish login.</p>
<form action=\"/opennds_preauth/\" method=\"get\">
<input type=\"hidden\" name=\"fas\" value=\"$fas\">
$customhtml
<input type=\"hidden\" name=\"landing\" value=\"yes\">
<input type=\"submit\" value=\"Continue\" class=\"btn\">
</form>"
		return
	fi

	echo "<div class=\"ok\">
<div class=\"ic\">&#x2705;</div>
<h1>Connecting...</h1>
<p>Please wait while internet access is enabled.</p>
</div>
<form id=\"continueForm\" action=\"/opennds_preauth/\" method=\"get\">
<input type=\"hidden\" name=\"fas\" value=\"$fas\">
$customhtml
<input type=\"hidden\" name=\"landing\" value=\"yes\">
<input type=\"submit\" value=\"Continue Browsing\" class=\"btn btn2\">
</form>
<script>
setTimeout(function(){document.getElementById('continueForm').submit();},100);
</script>"
}

read_terms() {
	:
}

#### end of functions ####

session_length="0"
upload_rate="0"
download_rate="0"
upload_quota="0"
download_quota="0"
quotas="$session_length $upload_rate $download_rate $upload_quota $download_quota"
ndscustomparams=""
ndscustomimages=""
ndscustomfiles=""
ndsparamlist="$ndsparamlist $ndscustomparams $ndscustomimages $ndscustomfiles"
additionalthemevars=""
fasvarlist="$fasvarlist $additionalthemevars"
userinfo="$title"
