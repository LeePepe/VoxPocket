#!/usr/bin/env python3
"""执行真实 workflow 的 freshness 脚本；只替换时钟，不构建或上传 App。"""
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/testflight.yml"


class TestFlightScheduleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = WORKFLOW.read_text()
        freshness = cls.workflow.split("  freshness:\n", 1)[1].split("\n  release:", 1)[0]
        cls.script = textwrap.dedent(freshness.split("        run: |\n", 1)[1])
        cls.defaults = dict(re.findall(r'^          (\w+): "(\d+)"$', freshness, re.M))

    def run_gate(self, schedule, day, hour, minute, event="schedule"):
        # 测试新脚本和旧主线均使用同一虚拟时钟，避免复制被测计算逻辑。
        clock = """
date() {
  case "$*" in
    '-u +%w %H %M') printf '%s %s %s\\n' "$TEST_DAY" "$TEST_HOUR" "$TEST_MINUTE" ;;
    '-u +%H') printf '%s\\n' "$TEST_HOUR" ;;
    '-u +%M') printf '%s\\n' "$TEST_MINUTE" ;;
    *) echo 'Unexpected date invocation' >&2; return 1 ;;
  esac
}
"""
        with tempfile.TemporaryDirectory(prefix="voxpocket-schedule-test-") as directory:
            output = Path(directory) / "github-output"
            result = subprocess.run(
                ["/bin/bash", "--noprofile", "--norc", "-c", clock + self.script],
                env={
                    "PATH": "/usr/bin:/bin", "EVENT_NAME": event,
                    "EVENT_SCHEDULE": schedule, "GITHUB_OUTPUT": str(output),
                    "TEST_DAY": str(day), "TEST_HOUR": f"{hour:02d}",
                    "TEST_MINUTE": f"{minute:02d}", **self.defaults,
                },
                cwd=directory, capture_output=True, text=True, timeout=5,
            )
            return result, output.read_text() if output.exists() else ""

    def assert_gate(self, day, delay, proceed):
        elapsed = 19 * 60 + delay
        result, output = self.run_gate(
            f"0 19 * * {day}", (day + elapsed // 1440) % 7,
            (elapsed % 1440) // 60, elapsed % 60,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, f"proceed={'true' if proceed else 'false'}\n")
        self.assertIn(f"current delay is {delay} minute(s)", result.stdout)

    def test_schedule_preserves_one_daily_1900_utc_slot(self):
        schedules = re.findall(r'^    - cron: "([^"]+)"', self.workflow, re.M)
        self.assertEqual(schedules, [f"0 19 * * {day}" for day in range(7)])
        self.assertIn("EVENT_SCHEDULE: ${{ github.event.schedule }}", self.workflow)
        self.assertEqual(self.defaults, {
            "SCHEDULED_UTC_HOUR": "19", "SCHEDULED_UTC_MINUTE": "0",
            "MAX_DELAY_MINUTES": "60",
        })

    def test_on_time_and_inclusive_deadline_each_weekday(self):
        for day in range(7):
            for delay in (0, 30, 60):
                with self.subTest(day=day, delay=delay):
                    self.assert_gate(day, delay, True)

    def test_stale_jobs_do_not_wrap_at_midnight_or_week_boundary(self):
        # 包含原缺陷：24h30m；星期六跨星期日仍必须拒绝。
        # 星期标签不能区分相隔整周的事件，不宣称覆盖 >=7 天的延迟。
        for day in range(7):
            for delay in (61, 300, 1440, 1470, 1500, 6 * 1440 + 30):
                with self.subTest(day=day, delay=delay):
                    self.assert_gate(day, delay, False)

    def test_same_weekday_before_slot_means_previous_week(self):
        result, output = self.run_gate("0 19 * * 0", 0, 18, 59)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "proceed=false\n")
        self.assertIn("current delay is 10079 minute(s)", result.stdout)

    def test_manual_dispatch_does_not_require_a_schedule(self):
        result, output = self.run_gate("", 0, 12, 0, event="workflow_dispatch")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "proceed=true\n")
        self.assertIn("Manual dispatch", result.stdout)

    def test_unknown_weekday_fails_closed(self):
        for schedule in ("", "0 19 * * *", "0 19 * * 7", "0 19 * * sun"):
            with self.subTest(schedule=schedule):
                result, output = self.run_gate(schedule, 0, 19, 0)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("proceed=true", output)
                self.assertIn("Unexpected schedule expression", result.stdout)


if __name__ == "__main__":
    unittest.main()
