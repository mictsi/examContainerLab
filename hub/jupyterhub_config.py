# jupyterhub_config.py — multi-user exam front-end (variant "hub")
#
# Accounts, passwords and lab access live in hub/userlist (bind-mounted
# read-only at /srv/jupyterhub/hub/userlist). One line per account:
#
#     username:password:lab[:admin]        lab = full | python | both
#
# There is no self-registration: only listed accounts can log in, so an
# instructor provisions exam access by editing that one file. User and
# password edits apply on the next login without restarting the hub; the
# admin flag is also evaluated at login time.
#
# The hub spawns one lab container per student (DockerSpawner) from the same
# images the standalone labs use, with the same rootless hardening. Student
# work lands in results/<username>/ on the host.

import hmac
import os
import sys

from jupyterhub.auth import Authenticator

USERLIST = os.environ.get("USERLIST_FILE", "/srv/jupyterhub/hub/userlist")

IMAGES = {
    "full": os.environ.get("FULL_IMAGE", "exam-jupyterlab:demo"),
    "python": os.environ.get("PYTHON_IMAGE", "exam-jupyterlab-python:demo"),
}

# Host path of the repo — bind-mount sources for the spawned containers must
# be host paths, not paths inside the hub container.
HOST_DIR = os.environ["EXAM_HOST_DIR"].rstrip("/")


def load_userlist():
    """Parse USERLIST into {username: {password, lab, admin}}.

    Re-read on every login / spawn so edits apply without a hub restart.
    """
    users = {}
    with open(USERLIST) as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split(":")
            if len(fields) < 3 or fields[2] not in ("full", "python", "both"):
                print(f"userlist:{lineno}: skipping malformed line")
                continue
            name, password, lab = fields[:3]
            users[name] = {
                "password": password,
                "lab": lab,
                "admin": "admin" in fields[3:],
            }
    return users


class UserListAuthenticator(Authenticator):
    """Static exam accounts from the userlist file — no self-registration."""

    async def authenticate(self, handler, data):
        user = load_userlist().get(data["username"])
        if user and hmac.compare_digest(user["password"], data["password"]):
            return {"name": data["username"], "admin": user["admin"]}
        return None


c.JupyterHub.authenticator_class = UserListAuthenticator
c.Authenticator.allow_all = True  # authenticate() itself is the whitelist

c.JupyterHub.spawner_class = "dockerspawner.DockerSpawner"


def allowed_images(spawner):
    """Labs this user may spawn; lab "both" renders a picker at spawn time."""
    lab = load_userlist().get(spawner.user.name, {}).get("lab")
    if lab == "both":
        return dict(IMAGES)
    return {lab: IMAGES[lab]} if lab in IMAGES else {}


def pre_spawn(spawner):
    # Fix the image for single-lab users (no picker is shown for them).
    lab = load_userlist().get(spawner.user.name, {}).get("lab")
    if lab in IMAGES:
        spawner.image = IMAGES[lab]
    # Pre-create the per-student results dir writable by jovyan (uid 1000) —
    # otherwise the docker daemon creates it root-owned on first mount.
    path = os.path.join("/srv/jupyterhub/results", spawner.user.name)
    os.makedirs(path, exist_ok=True)
    os.chown(path, 1000, 100)


c.DockerSpawner.allowed_images = allowed_images
c.Spawner.pre_spawn_hook = pre_spawn

c.DockerSpawner.image = IMAGES["python"]  # fallback; pre_spawn/picker override
c.DockerSpawner.pull_policy = "never"  # images are local (./run.sh build all)
c.DockerSpawner.name_template = "exam-user-{username}"
c.DockerSpawner.network_name = os.environ.get("DOCKER_NETWORK", "examnet")
c.DockerSpawner.use_internal_ip = True
c.DockerSpawner.remove = True  # drop the container when the server stops
c.DockerSpawner.notebook_dir = "/home/jovyan"
# Open the file browser in the writable results/ folder, not in $HOME —
# keeps students out of the read-only exams/ mount by default
c.Spawner.default_url = "/lab/tree/results"
c.DockerSpawner.mem_limit = os.environ.get("USER_MEM_LIMIT", "2G")
c.DockerSpawner.cpu_limit = float(os.environ.get("USER_CPU_LIMIT", "2"))

c.DockerSpawner.volumes = {
    f"{HOST_DIR}/exams": {"bind": "/home/jovyan/exams", "mode": "ro"},
    f"{HOST_DIR}/results/{{username}}": "/home/jovyan/results",
}

# Same rootless hardening as the standalone labs
c.DockerSpawner.extra_create_kwargs = {"user": "1000:100"}
c.DockerSpawner.extra_host_config = {
    "cap_drop": ["ALL"],
    "security_opt": ["no-new-privileges:true"],
}

c.JupyterHub.hub_ip = "0.0.0.0"
c.JupyterHub.hub_connect_ip = os.environ.get("HUB_CONNECT_IP", "examhub")

# Hub state (DB, cookie secret) on a named volume so a hub restart does not
# log everyone out or lose track of running student containers.
c.JupyterHub.db_url = "sqlite:///state/jupyterhub.sqlite"
c.JupyterHub.cookie_secret_file = "/srv/jupyterhub/state/cookie_secret"

# Stop servers idle for IDLE_TIMEOUT seconds (default 1 h); remove=True above
# then deletes the container. Student work survives in results/<username>/ and
# the next login simply spawns a fresh container.
idle_timeout = int(os.environ.get("IDLE_TIMEOUT", "3600"))
c.JupyterHub.services = [
    {
        "name": "idle-culler",
        "command": [
            sys.executable,
            "-m",
            "jupyterhub_idle_culler",
            f"--timeout={idle_timeout}",
            f"--cull-every={max(30, idle_timeout // 4)}",
        ],
    }
]
c.JupyterHub.load_roles = [
    {
        "name": "idle-culler",
        "scopes": ["list:users", "read:users:activity", "read:servers", "delete:servers"],
        "services": ["idle-culler"],
    }
]
