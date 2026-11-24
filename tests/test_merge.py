"""Tests for callscribe-merge: interleaving two whisper.cpp JSON transcripts."""

import json
import os
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "callscribe-merge")


def seg(from_ms, to_ms, text):
    return {"offsets": {"from": from_ms, "to": to_ms}, "text": text}


class MergeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def jfile(self, name, obj):
        path = os.path.join(self.tmp.name, name)
        with open(path, "w") as f:
            if isinstance(obj, str):
                f.write(obj)
            else:
                json.dump(obj, f)
        return path

    def merge(self, you, them):
        return subprocess.run([SCRIPT, you, them], capture_output=True, text=True)

    def test_interleaves_by_offset(self):
        you = self.jfile("you.json", {"transcription": [seg(0, 1500, " hello"), seg(5000, 6000, " bye")]})
        them = self.jfile("them.json", {"transcription": [seg(2000, 3000, " hi there")]})
        r = self.merge(you, them)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(
            r.stdout,
            "**[0:00:00] You:** hello\n"
            "**[0:00:02] Them:** hi there\n"
            "**[0:00:05] You:** bye\n",
        )

    def test_tie_goes_to_you(self):
        you = self.jfile("you.json", {"transcription": [seg(1000, 2000, "a")]})
        them = self.jfile("them.json", {"transcription": [seg(1000, 2000, "b")]})
        r = self.merge(you, them)
        self.assertEqual(
            r.stdout,
            "**[0:00:01] You:** a\n**[0:00:01] Them:** b\n",
        )

    def test_empty_transcription_in_one_file(self):
        you = self.jfile("you.json", {"transcription": [seg(0, 1000, "solo")]})
        them = self.jfile("them.json", {"transcription": []})
        r = self.merge(you, them)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "**[0:00:00] You:** solo\n")

    def test_missing_transcription_key_is_empty(self):
        you = self.jfile("you.json", {"transcription": [seg(0, 1000, "solo")]})
        them = self.jfile("them.json", {})
        r = self.merge(you, them)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "**[0:00:00] You:** solo\n")

    def test_whitespace_segments_dropped(self):
        you = self.jfile("you.json", {"transcription": [seg(0, 500, "   "), seg(1000, 2000, "real")]})
        them = self.jfile("them.json", {"transcription": []})
        r = self.merge(you, them)
        self.assertEqual(r.stdout, "**[0:00:01] You:** real\n")

    def test_hour_formatting(self):
        you = self.jfile("you.json", {"transcription": [seg(3723000, 3724000, "late")]})
        them = self.jfile("them.json", {"transcription": []})
        r = self.merge(you, them)
        self.assertEqual(r.stdout, "**[1:02:03] You:** late\n")

    def test_malformed_json_exits_1(self):
        you = self.jfile("you.json", "{not json")
        them = self.jfile("them.json", {"transcription": []})
        r = self.merge(you, them)
        self.assertEqual(r.returncode, 1)
        self.assertNotEqual(r.stderr, "")

    def test_unreadable_file_exits_1(self):
        them = self.jfile("them.json", {"transcription": []})
        r = self.merge(os.path.join(self.tmp.name, "absent.json"), them)
        self.assertEqual(r.returncode, 1)
        self.assertNotEqual(r.stderr, "")


if __name__ == "__main__":
    unittest.main()
