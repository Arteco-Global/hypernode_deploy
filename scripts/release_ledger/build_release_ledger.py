#!/usr/bin/env python3
import json
import os
import re
import sys
import textwrap
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


BUILD_LABEL_RE = re.compile(
    r"Build label:\s*"
    r"tag=(?P<tag>[^|]+)\|"
    r"backend=(?P<backend_branch>[^@|]+)@(?P<backend_sha>[^|]+)\|"
    r"export=(?P<export_branch>[^@|]+)@(?P<export_sha>[^|]+)\|"
    r"configurator=(?P<configurator_branch>[^@|]+)@(?P<configurator_sha>[^|]+)\|"
    r"services=(?P<services>[^|]+)\|"
    r"run=(?P<run_number>\d+)\|"
    r"built_at=(?P<built_at>.+)$"
)

BACKEND_SERVICES = {
    "live_streamer",
    "id_verifier",
    "event_manager",
    "metadata",
    "suite_manager",
    "media_recorder",
    "snapshot_recorder",
    "web_server",
    "port_broker",
    "message_broker",
    "database",
    "coretrust",
    "watchdog",
}

COMPONENT_REPOS = {
    "backend": "Arteco-Global/hypernode-server",
    "configurator": "Arteco-Global/hypernode_server_gui",
    "export": "Arteco-Global/arteco-export-service",
}


class LedgerError(RuntimeError):
    pass


@dataclass
class Config:
    token: str
    target_repository: str
    run_id_or_url: str
    tag_filter: str
    resolution_mode: str
    ledger_json_path: Path
    ledger_md_path: Path


def load_config() -> Config:
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        raise LedgerError("GITHUB_TOKEN is required.")

    target_repository = os.environ.get("TARGET_REPOSITORY", "").strip()
    if not target_repository:
        raise LedgerError("TARGET_REPOSITORY is required.")

    run_id_or_url = os.environ.get("RUN_ID_OR_URL", "").strip()
    if not run_id_or_url:
        raise LedgerError("RUN_ID_OR_URL is required.")

    resolution_mode = os.environ.get("RESOLUTION_MODE", "strict").strip()
    if resolution_mode not in {"strict", "best-effort"}:
        raise LedgerError("RESOLUTION_MODE must be 'strict' or 'best-effort'.")

    return Config(
        token=token,
        target_repository=target_repository,
        run_id_or_url=run_id_or_url,
        tag_filter=os.environ.get("TAG_FILTER", "latest").strip(),
        resolution_mode=resolution_mode,
        ledger_json_path=Path("release_ledger.json"),
        ledger_md_path=Path("release_ledger.md"),
    )


def extract_run_id(value: str) -> int:
    stripped = value.strip()
    if stripped.isdigit():
        return int(stripped)

    match = re.search(r"/actions/runs/(\d+)", stripped)
    if match:
        return int(match.group(1))

    raise LedgerError(f"Unable to parse run id from input: {value}")


def github_request(
    config: Config,
    url: str,
    *,
    accept: str = "application/vnd.github+json",
) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": accept,
            "Authorization": f"Bearer {config.token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "hypernode-deploy-release-ledger",
        },
    )

    try:
        with urllib.request.urlopen(request) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise LedgerError(f"GitHub API error on {url}: HTTP {exc.code}: {body}") from exc


def github_json(config: Config, url: str) -> dict:
    return json.loads(github_request(config, url).decode("utf-8"))


def download_logs(config: Config, logs_url: str) -> zipfile.ZipFile:
    raw = github_request(config, logs_url)
    return zipfile.ZipFile(BytesIO(raw))


def find_build_label(log_zip: zipfile.ZipFile) -> Dict[str, str]:
    labels: List[Dict[str, str]] = []

    for name in log_zip.namelist():
        with log_zip.open(name) as handle:
            try:
                content = handle.read().decode("utf-8", errors="replace")
            except RuntimeError:
                continue

        for line in content.splitlines():
            match = BUILD_LABEL_RE.search(line.strip())
            if match:
                labels.append(match.groupdict())

    if not labels:
        raise LedgerError("No build label found in the workflow logs.")

    def canonicalize(label: Dict[str, str]) -> Dict[str, str]:
        canonical = dict(label)
        canonical.pop("built_at", None)
        return canonical

    unique_labels = {
        json.dumps(canonicalize(label), sort_keys=True): label
        for label in labels
    }
    if len(unique_labels) > 1:
        raise LedgerError("Multiple inconsistent build labels found in the workflow logs.")

    return next(iter(unique_labels.values()))


def direct_build_label_from_env() -> Optional[Dict[str, str]]:
    fields = {
        "tag": os.environ.get("DIRECT_TAG", "").strip(),
        "services": os.environ.get("DIRECT_SERVICES", "").strip(),
        "backend_branch": os.environ.get("DIRECT_BACKEND_BRANCH", "").strip(),
        "backend_sha": os.environ.get("DIRECT_BACKEND_SHA", "").strip(),
        "configurator_branch": os.environ.get("DIRECT_CONFIGURATOR_BRANCH", "").strip(),
        "configurator_sha": os.environ.get("DIRECT_CONFIGURATOR_SHA", "").strip(),
        "export_branch": os.environ.get("DIRECT_EXPORT_BRANCH", "").strip(),
        "export_sha": os.environ.get("DIRECT_EXPORT_SHA", "").strip(),
    }

    if not any(fields.values()):
        return None

    missing = [name for name, value in fields.items() if not value]
    if missing:
        raise LedgerError(
            "Direct release metadata is incomplete. Missing: " + ", ".join(sorted(missing))
        )

    return fields


def normalize_services(raw: str) -> List[str]:
    services = [part.strip() for part in raw.split(",") if part.strip()]
    if raw.strip() == "all":
        return ["all"]
    return services


def affected_components(services: List[str]) -> List[str]:
    if services == ["all"]:
        return ["backend", "configurator", "export"]

    affected: List[str] = []
    if "configurator" in services:
        affected.append("configurator")
    if "export" in services:
        affected.append("export")
    if any(service in BACKEND_SERVICES for service in services):
        affected.append("backend")
    return affected


def load_ledger(path: Path) -> dict:
    if not path.exists():
        return {"entries": []}

    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if "entries" not in data or not isinstance(data["entries"], list):
        raise LedgerError(f"Ledger file {path} has an invalid format.")
    return data


def select_previous_entry(entries: Iterable[dict], current_run_number: int, tag: str) -> Optional[dict]:
    candidates = [
        entry for entry in entries
        if entry.get("tag") == tag
        and entry.get("requested_services") == ["all"]
        and int(entry.get("run_number", 0)) < current_run_number
    ]

    if not candidates:
        return None

    return sorted(candidates, key=lambda entry: int(entry["run_number"]))[-1]


def compare_commits(config: Config, repository: str, base: str, head: str) -> List[str]:
    if base == head:
        return []

    url = f"https://api.github.com/repos/{repository}/compare/{base}...{head}"
    payload = github_json(config, url)
    return [commit["sha"] for commit in payload.get("commits", [])]


def prs_for_commit(config: Config, repository: str, sha: str) -> List[dict]:
    url = f"https://api.github.com/repos/{repository}/commits/{sha}/pulls"
    payload = github_json(config, url)
    return payload if isinstance(payload, list) else []


def collect_prs(config: Config, repository: str, base: str, head: str) -> List[dict]:
    commits = compare_commits(config, repository, base, head)
    if not commits:
        return []

    collected: Dict[int, dict] = {}
    for sha in commits:
        for pr in prs_for_commit(config, repository, sha):
            number = pr.get("number")
            merged_at = pr.get("merged_at")
            head_ref = ((pr.get("head") or {}).get("ref"))
            title = pr.get("title")
            url = pr.get("html_url")

            if not number or not merged_at or not head_ref or not title or not url:
                continue

            collected[number] = {
                "number": number,
                "title": title,
                "branch": head_ref,
                "url": url,
                "merged_at": merged_at,
            }

    return sorted(collected.values(), key=lambda pr: (pr["merged_at"], pr["number"]))


def build_entry(config: Config, run: dict, label: Dict[str, str], ledger: dict) -> Tuple[dict, Optional[dict]]:
    tag = label["tag"]
    if config.tag_filter and tag != config.tag_filter:
        raise LedgerError(
            f"Run {run['id']} has tag '{tag}', expected '{config.tag_filter}'."
        )

    services = normalize_services(label["services"])
    current_run_number = int(label["run_number"])
    previous_entry = select_previous_entry(ledger["entries"], current_run_number, tag)
    involved = affected_components(services)

    components = {
        "backend": {
            "repository": COMPONENT_REPOS["backend"],
            "branch": label["backend_branch"],
            "sha": label["backend_sha"],
        },
        "configurator": {
            "repository": COMPONENT_REPOS["configurator"],
            "branch": label["configurator_branch"],
            "sha": label["configurator_sha"],
        },
        "export": {
            "repository": COMPONENT_REPOS["export"],
            "branch": label["export_branch"],
            "sha": label["export_sha"],
        },
    }

    for name, component in components.items():
        component["tracked_in_run"] = name in involved
        previous_sha = None
        if previous_entry:
            previous_component = (previous_entry.get(name) or {})
            previous_sha = previous_component.get("sha")

        component["previous_sha"] = previous_sha
        if not component["tracked_in_run"]:
            component["prs"] = []
            component["comparison_status"] = "not_included"
            continue

        if not previous_sha:
            component["prs"] = []
            component["comparison_status"] = "missing_previous_sha"
            continue

        try:
            component["prs"] = collect_prs(
                config,
                component["repository"],
                previous_sha,
                component["sha"],
            )
            component["comparison_status"] = "ok"
        except LedgerError:
            if config.resolution_mode == "strict":
                raise
            component["prs"] = []
            component["comparison_status"] = "best_effort_failed"

    status = "exact"
    if any(
        component["tracked_in_run"] and component["comparison_status"] != "ok"
        for component in components.values()
    ):
        status = "partial"

    return {
        "run_id": run["id"],
        "run_number": current_run_number,
        "run_attempt": run["run_attempt"],
        "run_url": run["html_url"],
        "workflow_name": run["name"],
        "workflow_path": run["path"],
        "created_at": run["created_at"],
        "updated_at": run["updated_at"],
        "conclusion": run.get("conclusion"),
        "tag": tag,
        "requested_services": services,
        "resolution_mode": config.resolution_mode,
        "resolution_status": status,
        "baseline_run_number": previous_entry.get("run_number") if previous_entry else None,
        "backend": components["backend"],
        "configurator": components["configurator"],
        "export": components["export"],
    }, previous_entry


def prune_component(component: dict) -> dict:
    return {
        "repository": component["repository"],
        "branch": component["branch"],
        "sha": component["sha"],
        "previous_sha": component["previous_sha"],
        "tracked_in_run": component["tracked_in_run"],
        "comparison_status": component["comparison_status"],
        "prs": component["prs"],
    }


def persist_ledger(path: Path, ledger: dict, new_entry: dict) -> None:
    filtered_entries = [
        entry for entry in ledger["entries"]
        if int(entry.get("run_id", 0)) != int(new_entry["run_id"])
    ]
    filtered_entries.append(new_entry)
    filtered_entries.sort(key=lambda entry: int(entry["run_number"]))

    payload = {
        "entries": filtered_entries,
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def format_prs(prs: List[dict]) -> str:
    if not prs:
        return "-"
    return ", ".join(
        f"#{pr['number']} {pr['title']} ({pr['branch']})"
        for pr in prs
    )


def write_markdown(path: Path, ledger: dict) -> None:
    lines = [
        "# Release Ledger",
        "",
        "| Run | Tag | Services | Backend PRs | Configurator PRs | Export PRs |",
        "| --- | --- | --- | --- | --- | --- |",
    ]

    for entry in sorted(ledger["entries"], key=lambda item: int(item["run_number"])):
        services = ",".join(entry["requested_services"])
        lines.append(
            "| {run_number} | {tag} | {services} | {backend} | {configurator} | {export_} |".format(
                run_number=entry["run_number"],
                tag=entry["tag"],
                services=services,
                backend=format_prs(entry["backend"]["prs"]),
                configurator=format_prs(entry["configurator"]["prs"]),
                export_=format_prs(entry["export"]["prs"]),
            )
        )

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_summary(entry: dict, previous_entry: Optional[dict]) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return

    lines = [
        "## Release ledger entry",
        "",
        f"- Run: `{entry['run_number']}` ([link]({entry['run_url']}))",
        f"- Tag: `{entry['tag']}`",
        f"- Services: `{','.join(entry['requested_services'])}`",
        f"- Baseline run: `{previous_entry['run_number']}`" if previous_entry else "- Baseline run: `none`",
        f"- Resolution status: `{entry['resolution_status']}`",
        "",
    ]

    for component_name in ("backend", "configurator", "export"):
        component = entry[component_name]
        lines.extend([
            f"### {component_name}",
            "",
            f"- Branch: `{component['branch']}`",
            f"- SHA: `{component['sha']}`",
            f"- Previous SHA: `{component['previous_sha'] or 'n/a'}`",
            f"- Comparison status: `{component['comparison_status']}`",
            f"- PR count: `{len(component['prs'])}`",
            "",
        ])

    Path(summary_path).write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    try:
        config = load_config()
        run_id = extract_run_id(config.run_id_or_url)
        run = github_json(
            config,
            f"https://api.github.com/repos/{config.target_repository}/actions/runs/{run_id}",
        )
        direct_label = direct_build_label_from_env()
        if direct_label is not None:
            label = {
                **direct_label,
                "run_number": str(run["run_number"]),
                "built_at": run.get("updated_at", run.get("created_at", "")),
            }
        else:
            logs = download_logs(config, run["logs_url"])
            label = find_build_label(logs)
        ledger = load_ledger(config.ledger_json_path)
        entry, previous_entry = build_entry(config, run, label, ledger)

        persist_ledger(
            config.ledger_json_path,
            ledger,
            {
                **entry,
                "backend": prune_component(entry["backend"]),
                "configurator": prune_component(entry["configurator"]),
                "export": prune_component(entry["export"]),
            },
        )

        updated_ledger = load_ledger(config.ledger_json_path)
        write_markdown(config.ledger_md_path, updated_ledger)

        write_summary(entry, previous_entry)
        print(
            textwrap.dedent(
                f"""\
                Generated release ledger for run {entry['run_number']}.
                Output JSON: {config.ledger_json_path}
                Output Markdown: {config.ledger_md_path}
                """
            ).strip()
        )
        return 0
    except LedgerError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
