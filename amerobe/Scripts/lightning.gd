class_name LightningClient
extends Node

## Bitcoin Lightning payments for premium items.
##
## [b]This is compiled out of app-store builds.[/b] Apple's App Review Guideline
## 3.1.1 forbids using "cryptocurrencies and cryptocurrency wallets" to unlock
## content or functionality, so a store build must not ship this path at all.
## [method is_available] is the single gate; see docs/LIGHTNING.md.
##
## Flow:
##   1. request_invoice()  -> asks the backend for a BOLT11 invoice
##   2. invoice_ready      -> UI shows the invoice, offers a wallet deep link
##   3. poll every 2s      -> backend reports settled / not yet
##   4. payment_settled    -> caller grants the entitlement and saves
##
## The game never holds a node, a seed, or a spending key. It talks to a
## backend you control that has an *invoice-only* API key.

signal invoice_ready(item_id: String, bolt11: String, sats: int)
signal payment_settled(item_id: String)
signal payment_failed(item_id: String, reason: String)

## Where per-install configuration lives. Keeping it out of the binary means
## you can point a build at a different node without recompiling.
const CONFIG_PATH := "user://lightning.cfg"

const POLL_INTERVAL := 2.0
const INVOICE_TIMEOUT := 600.0
const REQUEST_TIMEOUT := 20.0

var base_url := ""
var invoice_key := ""

var _create_http: HTTPRequest
var _poll_http: HTTPRequest
var _poll_timer: Timer

var _active_item := ""
var _active_hash := ""
var _elapsed := 0.0
var _polling := false


# ---------------------------------------------------------------------------
# Availability
# ---------------------------------------------------------------------------

## True only where Lightning is permitted and configured.
##
## The `store_build` feature tag is set on the App Store / Play Store export
## presets. The `lightning` tag is set on the direct-download and desktop
## presets. Neither is present when running from the editor, so the editor
## check keeps development workable.
static func is_available() -> bool:
	if OS.has_feature("store_build"):
		return false
	return OS.has_feature("lightning") or OS.has_feature("editor")


## Availability plus a usable endpoint. The UI should call this one.
func is_configured() -> bool:
	return is_available() and not base_url.is_empty() and not invoice_key.is_empty()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_config()

	_create_http = HTTPRequest.new()
	_create_http.timeout = REQUEST_TIMEOUT
	_create_http.request_completed.connect(_on_create_completed)
	add_child(_create_http)

	_poll_http = HTTPRequest.new()
	_poll_http.timeout = REQUEST_TIMEOUT
	_poll_http.request_completed.connect(_on_poll_completed)
	add_child(_poll_http)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL
	_poll_timer.timeout.connect(_poll_once)
	add_child(_poll_timer)


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		# No config yet. Write a commented template so the first run tells the
		# operator exactly what to fill in.
		config.set_value("backend", "base_url", "")
		config.set_value("backend", "invoice_key", "")
		config.save(CONFIG_PATH)
		return

	base_url = String(config.get_value("backend", "base_url", "")).rstrip("/")
	invoice_key = String(config.get_value("backend", "invoice_key", ""))


# ---------------------------------------------------------------------------
# Purchase flow
# ---------------------------------------------------------------------------

## Asks the backend for an invoice. Only one purchase can be in flight.
func request_invoice(item_id: String, sats: int, memo: String) -> void:
	if not is_configured():
		payment_failed.emit(item_id, "Lightning is not configured on this build.")
		return
	if not _active_item.is_empty():
		payment_failed.emit(item_id, "Another payment is already in progress.")
		return
	if sats <= 0:
		payment_failed.emit(item_id, "Invalid amount.")
		return

	_active_item = item_id
	_active_hash = ""
	_elapsed = 0.0

	var body := JSON.stringify({
		"out": false,
		"amount": sats,
		"memo": memo,
		# Echoed back by LNbits; lets the backend correlate without trusting us.
		"extra": {"item": item_id},
	})

	var headers := PackedStringArray([
		"X-Api-Key: " + invoice_key,
		"Content-Type: application/json",
	])

	var err := _create_http.request(
		base_url + "/api/v1/payments", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_fail("Could not reach the payment server (error %d)." % err)


func cancel() -> void:
	_stop_polling()
	_active_item = ""
	_active_hash = ""


func _process(delta: float) -> void:
	if not _polling:
		return
	_elapsed += delta
	if _elapsed >= INVOICE_TIMEOUT:
		_fail("Invoice expired. Nothing was charged.")


# ---------------------------------------------------------------------------
# Backend responses
# ---------------------------------------------------------------------------

func _on_create_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if _active_item.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("Network error contacting the payment server.")
		return
	if code < 200 or code >= 300:
		_fail("Payment server returned HTTP %d." % code)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Payment server sent an unreadable response.")
		return

	var data: Dictionary = parsed
	var bolt11 := String(data.get("payment_request", data.get("bolt11", "")))
	_active_hash = String(data.get("payment_hash", data.get("checking_id", "")))

	if bolt11.is_empty() or _active_hash.is_empty():
		_fail("Payment server did not return an invoice.")
		return

	var sats := int(data.get("amount", 0))
	invoice_ready.emit(_active_item, bolt11, sats)
	_start_polling()


func _on_poll_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if _active_item.is_empty():
		return
	# A failed poll is not a failed payment — the invoice is still live, so
	# stay quiet and try again on the next tick.
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var data: Dictionary = parsed
	# LNbits reports {"paid": true}; some deployments nest it under "details".
	var paid := bool(data.get("paid", false))
	if not paid and data.has("details"):
		var details: Variant = data.get("details")
		if typeof(details) == TYPE_DICTIONARY:
			paid = bool((details as Dictionary).get("paid", false))

	if paid:
		var item := _active_item
		_stop_polling()
		_active_item = ""
		_active_hash = ""
		payment_settled.emit(item)


func _start_polling() -> void:
	_polling = true
	_poll_timer.start()
	_poll_once()


func _stop_polling() -> void:
	_polling = false
	if is_instance_valid(_poll_timer):
		_poll_timer.stop()


func _poll_once() -> void:
	if _active_hash.is_empty():
		return
	var headers := PackedStringArray(["X-Api-Key: " + invoice_key])
	_poll_http.request(
		base_url + "/api/v1/payments/" + _active_hash.uri_encode(),
		headers, HTTPClient.METHOD_GET)


func _fail(reason: String) -> void:
	var item := _active_item
	_stop_polling()
	_active_item = ""
	_active_hash = ""
	if not item.is_empty():
		payment_failed.emit(item, reason)


# ---------------------------------------------------------------------------
# Wallet handoff
# ---------------------------------------------------------------------------

## Opens the invoice in the device's default Lightning wallet.
##
## On Android and iOS this is by far the best UX — the wallet app opens with
## the amount pre-filled. On desktop it works if a wallet has registered the
## `lightning:` scheme; if not, the UI still shows the copyable invoice text.
static func open_in_wallet(bolt11: String) -> void:
	if bolt11.is_empty():
		return
	OS.shell_open("lightning:" + bolt11)


static func copy_to_clipboard(bolt11: String) -> void:
	DisplayServer.clipboard_set(bolt11)
