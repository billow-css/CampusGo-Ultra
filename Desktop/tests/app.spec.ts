import { test, expect } from "@playwright/test";

test("four pages preserve original layout and themes", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("/");
  await page.getByRole("button", { name: "先看示例", exact: true }).click();
  await expect(page.locator(".course").first()).toBeVisible();
  await page.screenshot({
    path: "test-results/previews/schedule.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "摘要", exact: true }).click();
  await expect(page.locator(".hero-main h1")).toBeVisible();
  await page.screenshot({
    path: "test-results/previews/summary.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "作业与日程", exact: true }).click();
  await expect(page.locator(".work-dash")).toHaveCount(2);
  await page.getByRole("button", { name: "发现", exact: true }).click();
  await expect(page.locator(".module-card")).toHaveCount(2);
  await page.getByRole("button", { name: "主题", exact: true }).click();
  await page.getByLabel("界面模式").selectOption("dark");
  await page.getByRole("button", { name: "关闭", exact: true }).click();
  await expect(page.locator(".app")).toHaveAttribute("data-theme", "dark");
  await page.screenshot({
    path: "test-results/previews/discover-dark.png",
  });
  expect(errors).toEqual([]);
});
test("todo writes survive reload without importing demo data", async ({
  page,
}) => {
  await page.goto("/");
  await page.getByRole("button", { name: "添加日程", exact: true }).click();
  await page.getByLabel("标题", { exact: true }).fill("测试日程");
  await page.getByRole("button", { name: "保存", exact: true }).click();
  await expect(page.getByText("测试日程", { exact: true })).toBeVisible();
  await page.waitForTimeout(350);
  await page.reload();
  await expect(page.getByText("测试日程", { exact: true })).toBeVisible();
  await page.getByText("测试日程", { exact: true }).click();
  await expect(
    page.locator(".task input[type=checkbox]").first(),
  ).toBeChecked();
});
test("homework accepts multiline items and tracks completion", async ({
  page,
}) => {
  await page.goto("/");
  await page.getByRole("button", { name: "先看示例", exact: true }).click();
  await page.getByRole("button", { name: "添加作业", exact: true }).click();
  await page.getByLabel("标题", { exact: true }).fill("新作业");
  await page
    .getByLabel("科目", { exact: true })
    .selectOption({ label: "程序设计" });
  await page.getByLabel("子作业条目").fill("第一题\n第二题");
  await page.getByRole("button", { name: "保存", exact: true }).click();
  const card = page.locator(".homework").filter({ hasText: "新作业" });
  await expect(card).toContainText(/H\d{4}/);
  await expect(card.getByRole("checkbox")).toHaveCount(2);
  await card.getByText("第一题", { exact: true }).click();
  await expect(card).toContainText("1/2 已完成");
});
test("ICS import updates real timetable through worker", async ({ page }) => {
  await page.goto("/");
  const start = new Date();
  start.setHours(10, 10, 0, 0);
  const stamp = (d: Date) =>
    d
      .toISOString()
      .replace(/[-:]/g, "")
      .replace(/\.\d{3}/, "");
  const ics = `BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:test-course\r\nDTSTART:${stamp(start)}\r\nDTEND:${stamp(new Date(+start + 6000000))}\r\nSUMMARY:导入课程\r\nLOCATION:A302\r\nEND:VEVENT\r\nEND:VCALENDAR`;
  await page
    .locator('input[type=file][accept*=".ics"]')
    .setInputFiles({
      name: "sample.ics",
      mimeType: "text/calendar",
      buffer: Buffer.from(ics),
    });
  await expect(
    page.locator(".course").filter({ hasText: "导入课程" }),
  ).toBeVisible();
  await page.waitForTimeout(350);
  await page.reload();
  await expect(
    page.locator(".course").filter({ hasText: "导入课程" }),
  ).toBeVisible();
  await page.locator(".course").filter({ hasText: "导入课程" }).click();
  await page.getByRole("button", { name: "将此课次标记为考试" }).click();
  await expect(page.locator(".course.exam")).toHaveCount(1);
});
