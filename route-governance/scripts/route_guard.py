#!/usr/bin/env python3
import argparse
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


VALID_STATUS = {
    "proposed",
    "active",
    "blocked",
    "failed",
    "suspended",
    "superseded",
    "completed",
}
VALID_OWNER = {"user_specified", "agent_selected", "fallback"}
VALID_COMMITMENT = {"locked", "preferred", "exploratory"}
VALID_EVENT_TYPE = {"probe", "execute", "recover", "verify", "route_change", "reflect"}
VALID_RESULT = {"success", "failure", "blocked"}
ERROR_FAMILIES = {
    "focus_missing",
    "control_missing",
    "timing_state",
    "permission_lock",
    "path_resolution",
    "encoding_format",
    "import_format",
    "compile_diagnostic",
    "verification_gap",
    "recovery_churn",
    "route_violation",
}


def now():
    return datetime.now(timezone.utc).isoformat()


def fail(message):
    print("FAIL: " + message, file=sys.stderr)
    raise SystemExit(1)


def load_state(path):
    p = Path(path)
    if not p.exists():
        fail(f"route state not found: {p}")
    return json.loads(p.read_text(encoding="utf-8"))


def save_state(path, state):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def get_active_route(state):
    active_id = state.get("active_route_id")
    routes = state.get("routes", {})
    if not active_id:
        fail("active_route_id is missing")
    if active_id not in routes:
        fail(f"active route {active_id!r} is missing from routes")
    active = routes[active_id]
    if active.get("status") != "active":
        fail(f"active route {active_id!r} has status {active.get('status')!r}, expected 'active'")
    active_count = sum(1 for r in routes.values() if r.get("status") == "active")
    if active_count != 1:
        fail(f"expected exactly one active route, found {active_count}")
    return active_id, active


def get_current_route_for_switch(state):
    active_id = state.get("active_route_id")
    routes = state.get("routes", {})
    if not active_id:
        fail("active_route_id is missing")
    if active_id not in routes:
        fail(f"current route {active_id!r} is missing from routes")
    current = routes[active_id]
    if current.get("status") not in {"active", "blocked", "failed"}:
        fail(f"current route {active_id!r} has status {current.get('status')!r}; switch requires active, blocked, or failed")
    return active_id, current


def route_template(args):
    owner = args.owner
    commitment = args.commitment
    if owner not in VALID_OWNER:
        fail(f"invalid owner: {owner}")
    if commitment not in VALID_COMMITMENT:
        fail(f"invalid commitment: {commitment}")
    return {
        "route_id": args.route_id,
        "status": "active",
        "owner": owner,
        "commitment_level": commitment,
        "reason_selected": args.reason or "",
        "created_at": now(),
        "last_updated": now(),
        "preconditions": args.precondition or [],
        "action_surface": {
            "allowed": sorted(set(args.allowed or [])),
            "forbidden": sorted(set(args.forbidden or [])),
        },
        "observation_surface": args.observation_rule or [],
        "failure_boundary": args.failure_boundary or [],
        "automatic_fallback_allowed": bool(args.automatic_fallback_allowed),
    }


def cmd_init(args):
    state = {
        "schema_version": 1,
        "task": args.task,
        "created_at": now(),
        "updated_at": now(),
        "active_route_id": args.route_id,
        "routes": {args.route_id: route_template(args)},
        "attempts": [],
        "route_changes": [],
        "reflections": [],
    }
    save_state(args.state, state)
    print(f"OK: initialized {args.state}")


def ensure_surface_allowed(route, surface):
    allowed = set(route.get("action_surface", {}).get("allowed", []))
    forbidden = set(route.get("action_surface", {}).get("forbidden", []))
    if surface in forbidden:
        fail(f"attempted action surface {surface!r} is forbidden by active route {route.get('route_id')!r}")
    if allowed and surface not in allowed:
        fail(f"attempted action surface {surface!r} is not allowed by active route {route.get('route_id')!r}; allowed={sorted(allowed)}")


def cmd_attempt(args):
    state = load_state(args.state)
    active_id, active = get_active_route(state)
    if args.route_id != active_id:
        fail(f"attempt route {args.route_id!r} does not match active route {active_id!r}")
    if args.event_type not in VALID_EVENT_TYPE:
        fail(f"invalid event type: {args.event_type}")
    ensure_surface_allowed(active, args.surface)
    state_change = parse_bool(args.state_change)
    if args.event_type == "probe" and state_change:
        fail("probe events must not modify target state; use execute, recover, or verify")
    if args.event_type == "recover" and (not args.recovery_hypothesis or not args.post_recovery_verification):
        fail("recover events require --recovery-hypothesis and --post-recovery-verification")
    if args.error_family and args.error_family not in ERROR_FAMILIES:
        fail(f"unknown error family {args.error_family!r}; use a fixed family")
    attempt = {
        "time": now(),
        "event_type": args.event_type,
        "route_id": args.route_id,
        "surface": args.surface,
        "action": args.action,
        "state_change": state_change,
        "observation": args.observation,
        "result": args.result,
        "failure_signature": args.failure_signature or "",
        "error_family": args.error_family or "",
        "evidence": args.evidence or "",
        "recovery_hypothesis": args.recovery_hypothesis or "",
        "post_recovery_verification": args.post_recovery_verification or "",
    }
    state.setdefault("attempts", []).append(attempt)
    state["updated_at"] = now()
    save_state(args.state, state)
    print("OK: attempt recorded")


def parse_bool(value):
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "y", "on"}:
        return True
    if text in {"0", "false", "no", "n", "off"}:
        return False
    fail(f"invalid boolean value: {value}")


def cmd_status(args):
    state = load_state(args.state)
    route_id = args.route_id or state.get("active_route_id")
    route = state.get("routes", {}).get(route_id)
    if not route:
        fail(f"route not found: {route_id}")
    if args.status not in VALID_STATUS:
        fail(f"invalid status: {args.status}")
    route["status"] = args.status
    route["last_updated"] = now()
    state["updated_at"] = now()
    if args.status == "active":
        for rid, other in state.get("routes", {}).items():
            if rid != route_id and other.get("status") == "active":
                other["status"] = "superseded"
        state["active_route_id"] = route_id
    save_state(args.state, state)
    print("OK: status updated")


def cmd_reflect(args):
    state = load_state(args.state)
    reflection = {
        "time": now(),
        "summary": args.summary,
        "classification": args.classification,
        "evidence": args.evidence or "",
    }
    state.setdefault("reflections", []).append(reflection)
    state["updated_at"] = now()
    save_state(args.state, state)
    print("OK: reflection recorded")


def cmd_switch(args):
    state = load_state(args.state)
    active_id, active = get_current_route_for_switch(state)
    if args.from_route and args.from_route != active_id:
        fail(f"from_route {args.from_route!r} does not match active route {active_id!r}")
    allowed_without_user = (
        active.get("status") in {"blocked", "failed"}
        or active.get("automatic_fallback_allowed")
    )
    if active.get("owner") == "user_specified" and args.approved_by != "user" and not allowed_without_user:
        fail("route switch requires user approval because active route is user_specified and not blocked/failed")
    required = {
        "reason": args.reason,
        "evidence": args.evidence,
        "suspected_failure_mechanism": args.suspected_failure_mechanism,
        "why_new_route_addresses_mechanism": args.why_new_route_addresses_mechanism,
        "risks_created": args.risks_created,
        "verification_plan": args.verification_plan,
        "implementation_method_change": args.implementation_method_change,
        "route_identity_change": args.route_identity_change,
        "prior_route_review": args.prior_route_review,
        "new_success_evidence": args.new_success_evidence,
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        fail("route switch missing required gate fields: " + ", ".join(missing))
    if not args.reason or not args.evidence:
        fail("route switch requires both reason and evidence")
    if not parse_bool(args.implementation_method_change):
        fail("route switch refused: implementation method did not change; record an in-route correction instead")
    if args.route_identity_change.strip().lower() in {"none", "no", "unchanged", "same"}:
        fail("route switch refused: route identity is unchanged; record a reflection or patch event inside the active route instead")
    old = active
    old["status"] = "superseded"
    old["last_updated"] = now()
    new_args = argparse.Namespace(
        route_id=args.to_route,
        owner=args.to_owner,
        commitment=args.to_commitment,
        reason=args.reason,
        precondition=args.precondition,
        allowed=args.allowed,
        forbidden=args.forbidden,
        observation_rule=args.observation_rule,
        failure_boundary=args.failure_boundary,
        automatic_fallback_allowed=args.automatic_fallback_allowed,
    )
    new_route = route_template(new_args)
    state.setdefault("routes", {})[args.to_route] = new_route
    state["active_route_id"] = args.to_route
    state.setdefault("route_changes", []).append({
        "time": now(),
        "from": active_id,
        "to": args.to_route,
        "trigger": args.reason,
        "evidence": args.evidence,
        "suspected_failure_mechanism": args.suspected_failure_mechanism,
        "why_new_route_addresses_mechanism": args.why_new_route_addresses_mechanism,
        "risks_created": args.risks_created,
        "verification_plan": args.verification_plan,
        "implementation_method_change": parse_bool(args.implementation_method_change),
        "route_identity_change": args.route_identity_change,
        "prior_route_review": args.prior_route_review,
        "new_success_evidence": args.new_success_evidence,
        "approved_by": args.approved_by or "",
    })
    state["updated_at"] = now()
    save_state(args.state, state)
    print("OK: route switched")


def cmd_audit(args):
    state = load_state(args.state)
    active_id, active = get_active_route(state)
    failures = []
    attempts = state.get("attempts", [])
    changes = state.get("route_changes", [])
    reflections = state.get("reflections", [])

    allowed = set(active.get("action_surface", {}).get("allowed", []))
    forbidden = set(active.get("action_surface", {}).get("forbidden", []))
    for idx, attempt in enumerate(attempts, 1):
        if attempt.get("route_id") == active_id:
            surface = attempt.get("surface")
            if surface in forbidden:
                failures.append(f"attempt {idx} uses forbidden surface {surface!r}")
            if allowed and surface not in allowed:
                failures.append(f"attempt {idx} uses unallowed surface {surface!r}")
            if attempt.get("event_type") == "probe" and attempt.get("state_change"):
                failures.append(f"attempt {idx} is probe but state_change=true")
            if attempt.get("event_type") == "recover" and (
                not attempt.get("recovery_hypothesis") or not attempt.get("post_recovery_verification")
            ):
                failures.append(f"attempt {idx} is recover without hypothesis or post-recovery verification")

    if len(changes) >= args.max_route_changes:
        failures.append(f"route thrashing detected: {len(changes)} route changes, limit is {args.max_route_changes - 1}")

    active_attempts = [a for a in attempts if a.get("route_id") == active_id]
    sig_counts = Counter(
        a.get("failure_signature")
        for a in active_attempts
        if a.get("failure_signature") and a.get("result") in {"failure", "blocked"}
    )
    reflected = bool(reflections)
    for sig, count in sig_counts.items():
        if count >= args.repeat_failure_limit and not reflected:
            failures.append(f"repeated failure signature {sig!r} occurred {count} times without reflection")

    family_counts = Counter(
        a.get("error_family")
        for a in active_attempts
        if a.get("error_family") and a.get("result") in {"failure", "blocked"}
    )
    for family, count in family_counts.items():
        if count >= 3:
            failures.append(f"error family {family!r} occurred {count} times; route review required")
        elif count >= 2 and not reflected:
            failures.append(f"error family {family!r} occurred {count} times without reflection")

    if active.get("owner") == "user_specified" and active.get("commitment_level") == "locked":
        if "uia_menu_click" not in forbidden and "mouse_click" not in forbidden and "coordinate_click" not in forbidden:
            failures.append("locked user_specified route does not explicitly forbid risky alternate UI action surfaces")

    if failures:
        for item in failures:
            print("FAIL: " + item, file=sys.stderr)
        raise SystemExit(1)

    print(f"OK: audit passed; active_route={active_id}")


def build_parser():
    p = argparse.ArgumentParser(description="Route governance guardrail")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_route_fields(sp, include_task=False):
        sp.add_argument("--state", required=True)
        if include_task:
            sp.add_argument("--task", required=True)
        sp.add_argument("--route-id", required=True)
        sp.add_argument("--owner", choices=sorted(VALID_OWNER), default="agent_selected")
        sp.add_argument("--commitment", choices=sorted(VALID_COMMITMENT), default="preferred")
        sp.add_argument("--reason", default="")
        sp.add_argument("--precondition", action="append")
        sp.add_argument("--allowed", action="append")
        sp.add_argument("--forbidden", action="append")
        sp.add_argument("--observation-rule", action="append")
        sp.add_argument("--failure-boundary", action="append")
        sp.add_argument("--automatic-fallback-allowed", action="store_true")

    sp = sub.add_parser("init")
    add_route_fields(sp, include_task=True)
    sp.set_defaults(func=cmd_init)

    sp = sub.add_parser("attempt")
    sp.add_argument("--state", required=True)
    sp.add_argument("--route-id", required=True)
    sp.add_argument("--surface", required=True)
    sp.add_argument("--event-type", choices=sorted(VALID_EVENT_TYPE), required=True)
    sp.add_argument("--action", required=True)
    sp.add_argument("--state-change", required=True)
    sp.add_argument("--observation", required=True)
    sp.add_argument("--result", choices=sorted(VALID_RESULT), required=True)
    sp.add_argument("--failure-signature", default="")
    sp.add_argument("--error-family", default="")
    sp.add_argument("--evidence", default="")
    sp.add_argument("--recovery-hypothesis", default="")
    sp.add_argument("--post-recovery-verification", default="")
    sp.set_defaults(func=cmd_attempt)

    sp = sub.add_parser("status")
    sp.add_argument("--state", required=True)
    sp.add_argument("--route-id")
    sp.add_argument("--status", required=True, choices=sorted(VALID_STATUS))
    sp.set_defaults(func=cmd_status)

    sp = sub.add_parser("reflect")
    sp.add_argument("--state", required=True)
    sp.add_argument("--summary", required=True)
    sp.add_argument("--classification", required=True)
    sp.add_argument("--evidence", default="")
    sp.set_defaults(func=cmd_reflect)

    sp = sub.add_parser("switch")
    sp.add_argument("--state", required=True)
    sp.add_argument("--from-route")
    sp.add_argument("--to-route", required=True)
    sp.add_argument("--to-owner", choices=sorted(VALID_OWNER), default="fallback")
    sp.add_argument("--to-commitment", choices=sorted(VALID_COMMITMENT), default="preferred")
    sp.add_argument("--reason", required=True)
    sp.add_argument("--evidence", required=True)
    sp.add_argument("--suspected-failure-mechanism", required=True)
    sp.add_argument("--why-new-route-addresses-mechanism", required=True)
    sp.add_argument("--risks-created", required=True)
    sp.add_argument("--verification-plan", required=True)
    sp.add_argument("--implementation-method-change", required=True)
    sp.add_argument("--route-identity-change", required=True)
    sp.add_argument("--prior-route-review", required=True)
    sp.add_argument("--new-success-evidence", required=True)
    sp.add_argument("--approved-by", default="")
    sp.add_argument("--precondition", action="append")
    sp.add_argument("--allowed", action="append")
    sp.add_argument("--forbidden", action="append")
    sp.add_argument("--observation-rule", action="append")
    sp.add_argument("--failure-boundary", action="append")
    sp.add_argument("--automatic-fallback-allowed", action="store_true")
    sp.set_defaults(func=cmd_switch)

    sp = sub.add_parser("audit")
    sp.add_argument("--state", required=True)
    sp.add_argument("--max-route-changes", type=int, default=2)
    sp.add_argument("--repeat-failure-limit", type=int, default=2)
    sp.set_defaults(func=cmd_audit)

    return p


def main():
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
