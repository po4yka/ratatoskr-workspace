import assert from "node:assert/strict"
import AxeBuilder from "@axe-core/playwright"
import { chromium } from "playwright"

const baseURL = process.env.COMPOSE_WEB_URL
const phase = process.argv[2] ?? "healthy"
assert(baseURL, "COMPOSE_WEB_URL is required")
assert(["healthy", "degraded"].includes(phase), `unknown phase: ${phase}`)

function seriousViolations(results) {
  return results.violations.filter(({ impact }) =>
    ["serious", "critical"].includes(impact)
  )
}

async function scan(page, route) {
  const results = await new AxeBuilder({ page }).analyze()
  assert.deepEqual(
    seriousViolations(results),
    [],
    `${route} has serious or critical axe violations`
  )
}

const browser = await chromium.launch()
try {
  const publicContext = await browser.newContext()
  const publicPage = await publicContext.newPage()
  await publicPage.goto(`${baseURL}/status`, { waitUntil: "networkidle" })
  await publicPage.getByRole("heading", { name: "System status" }).waitFor()
  const expectedState = phase === "healthy" ? "Operational" : "Degraded"
  await publicPage.getByText(expectedState, { exact: true }).first().waitFor()
  if (phase === "degraded") {
    const delivery = publicPage.getByRole("article").filter({
      has: publicPage.getByRole("heading", { name: "Command delivery" }),
    })
    await delivery.getByText("Unavailable", { exact: true }).waitFor()
    await delivery.getByText("Stale observation", { exact: true }).waitFor()
  }
  await scan(publicPage, `/status (${phase})`)

  if (phase === "healthy") {
    const ownerContext = await browser.newContext()
    await ownerContext.addInitScript(() => {
      sessionStorage.setItem(
        "ratatoskr.session.credential",
        "web012-owner-credential"
      )
    })
    const ownerPage = await ownerContext.newPage()
    await ownerPage.goto(`${baseURL}/ops`, { waitUntil: "networkidle" })
    await ownerPage.getByRole("heading", { name: "Recent operations" }).waitFor()
    await ownerPage.getByText("Failed", { exact: true }).waitFor()
    await ownerPage.getByText("Partially succeeded", { exact: true }).waitFor()

    const skip = ownerPage.getByRole("link", { name: "Skip to content" })
    await skip.focus()
    await ownerPage.keyboard.press("Enter")
    assert.equal(await ownerPage.locator("main").evaluate((node) => node === document.activeElement), true)

    await scan(ownerPage, "/ops")
    await ownerPage.getByRole("link", { name: "Schedules" }).click()
    const schedulesHeading = ownerPage.getByRole("heading", {
      name: "Schedule status",
    })
    await schedulesHeading.waitFor()
    assert.equal(await schedulesHeading.evaluate((node) => node === document.activeElement), true)
    await ownerPage.getByRole("link", { name: "Audit" }).click()
    await ownerPage.getByRole("heading", { name: "Audit trail" }).waitFor()
    await ownerContext.close()
  }

  await publicContext.close()

  process.stdout.write(`browser ${phase} smoke: PASS\n`)
} finally {
  await browser.close()
}
