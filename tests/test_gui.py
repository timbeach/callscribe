"""Headless tests for callscribe-gui's core logic (no Tk, no X)."""

import os
import tempfile
import textwrap
import time
import unittest
from importlib.machinery import SourceFileLoader

GUI_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "callscribe-gui")
gui = SourceFileLoader("callscribe_gui", GUI_PATH).load_module()

DEVICES_TEXT = (
    "source\tfake.mic\tFake Microphone\tselected\n"
    "source\tother.mic\tOther Microphone\t\n"
    "sink\tfake.sink\tFake Output\tselected\n"
    "sink\tgone.sink\t(missing)\tselected,missing\n"
)

PW_LINK_TEXT = textwrap.dedent("""\
    my.sink:monitor_FL
      |-> pw-record:input_FL
    my.sink:monitor_FR
      |-> pw-record:input_FR
    my.mic:capture_FL
      |-> pw-record:input_FL
    unrelated.sink:monitor_FL
      |-> some-app:input_FL
""")


def write(path, content):
    with open(path, "w") as f:
        f.write(content)


def transcript(session="20260101-120000", model="ggml-small.bin", extra=""):
    return (
        "---\n"
        "date: 2026-01-01\n"
        "start: 12:00\n"
        "duration_seconds: 120\n"
        "mic_device: m\n"
        "sys_device: s\n"
        + (f"session: {session}\n" if session else "")
        + (f"model: {model}\n" if model else "")
        + extra
        + "---\n\n**[0:00:01] You:** hi\n"
    )


class ParseTest(unittest.TestCase):
    def test_parse_devices(self):
        devs = gui.parse_devices(DEVICES_TEXT)
        self.assertEqual(len(devs), 4)
        self.assertEqual(devs[0], {"kind": "source", "name": "fake.mic", "desc": "Fake Microphone", "flags": {"selected"}})
        self.assertEqual(devs[1]["flags"], set())
        self.assertEqual(devs[3]["flags"], {"selected", "missing"})

    def test_parse_env(self):
        env = gui.parse_env("CALLSCRIBE_OUT_DIR=/a/b\nCALLSCRIBE_MIC_DEV=\n")
        self.assertEqual(env["OUT_DIR"], "/a/b")
        self.assertEqual(env["MIC_DEV"], "")

    def test_parse_status_idle(self):
        self.assertEqual(gui.parse_status("idle\n"), ("idle", None, None))

    def test_parse_status_recording(self):
        self.assertEqual(gui.parse_status("recording 20260101-120000 754s\n"), ("recording", "20260101-120000", 754))

    def test_parse_status_garbage(self):
        self.assertEqual(gui.parse_status("meta: not found\nweird\n"), ("unknown", None, None))

    def test_parse_links(self):
        self.assertEqual(gui.parse_links(PW_LINK_TEXT, "my.mic", "my.sink"), (True, True))

    def test_parse_links_missing(self):
        self.assertEqual(gui.parse_links(PW_LINK_TEXT, "absent.mic", "unrelated.sink"), (False, False))


class FrontmatterTest(unittest.TestCase):
    def test_reads_fields(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "t.md")
            write(p, transcript())
            fm = gui.read_frontmatter(p)
            self.assertEqual(fm["session"], "20260101-120000")
            self.assertEqual(fm["duration_seconds"], "120")

    def test_no_fences_gives_empty(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "t.md")
            write(p, "just text\n")
            self.assertEqual(gui.read_frontmatter(p), {})

    def test_missing_file_gives_empty(self):
        self.assertEqual(gui.read_frontmatter("/nonexistent/x.md"), {})


class ListTranscriptsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.out = os.path.join(self.tmp.name, "out")
        self.sessions = os.path.join(self.tmp.name, "sessions")
        os.makedirs(self.out)
        os.makedirs(self.sessions)

    def mksession(self, sid, with_wav=True):
        d = os.path.join(self.sessions, sid)
        os.makedirs(d, exist_ok=True)
        if with_wav:
            write(os.path.join(d, "mic.wav"), "x")

    def test_missing_out_dir_gives_empty(self):
        self.assertEqual(gui.list_transcripts("/nonexistent/dir", self.sessions), [])

    def test_ordering_and_fields(self):
        a = os.path.join(self.out, "2026-01-01-1200-call.md")
        b = os.path.join(self.out, "2026-01-02-1300-call.md")
        write(a, transcript(session="s1"))
        write(b, transcript(session="s2", model="ggml-medium.bin"))
        os.utime(a, (time.time() - 100, time.time() - 100))
        self.mksession("s1")
        self.mksession("s2")
        rows = gui.list_transcripts(self.out, self.sessions)
        self.assertEqual([r["path"] for r in rows], [b, a])
        self.assertEqual(rows[0]["model"], "ggml-medium.bin")
        self.assertEqual(rows[0]["duration_seconds"], 120)
        self.assertTrue(rows[0]["rerunnable"])

    def test_summary_files_excluded(self):
        write(os.path.join(self.out, "2026-01-01-1200-call.md"), transcript())
        write(os.path.join(self.out, "2026-01-01-1200-call.summary.md"), "summary")
        rows = gui.list_transcripts(self.out, self.sessions)
        self.assertEqual(len(rows), 1)

    def test_pre_gui_transcript_not_rerunnable(self):
        write(os.path.join(self.out, "old-call.md"), transcript(session=None, model=None))
        rows = gui.list_transcripts(self.out, self.sessions)
        self.assertIsNone(rows[0]["session"])
        self.assertFalse(rows[0]["rerunnable"])

    def test_cleaned_session_not_rerunnable(self):
        write(os.path.join(self.out, "2026-01-01-1200-call.md"), transcript(session="s3"))
        self.mksession("s3", with_wav=False)
        rows = gui.list_transcripts(self.out, self.sessions)
        self.assertFalse(rows[0]["rerunnable"])


class ConfigTest(unittest.TestCase):
    def test_preserves_unrelated_lines(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "config")
            original = "# my comment\nCALLSCRIBE_OUT_DIR='/keep/me'\nCALLSCRIBE_MIC_DEV='old.mic'\n"
            write(p, original)
            gui.set_config_values(p, {"CALLSCRIBE_MIC_DEV": "new.mic", "CALLSCRIBE_SYS_DEV": "new.sink"})
            with open(p) as f:
                result = f.read()
            self.assertIn("# my comment\n", result)
            self.assertIn("CALLSCRIBE_OUT_DIR='/keep/me'\n", result)
            self.assertIn("CALLSCRIBE_MIC_DEV='new.mic'\n", result)
            self.assertIn("CALLSCRIBE_SYS_DEV='new.sink'\n", result)
            self.assertNotIn("old.mic", result)

    def test_creates_file_and_parent(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "sub", "config")
            gui.set_config_values(p, {"CALLSCRIBE_MIC_DEV": "m"})
            with open(p) as f:
                self.assertIn("CALLSCRIBE_MIC_DEV='m'\n", f.read())


class MediumPathTest(unittest.TestCase):
    def test_sibling(self):
        self.assertEqual(
            gui.medium_model_path("/home/x/.local/share/callscribe/models/ggml-small.bin"),
            "/home/x/.local/share/callscribe/models/ggml-medium.bin",
        )


if __name__ == "__main__":
    unittest.main()
