import { describe, expect, test } from "bun:test";
import { GET } from "./route";

function context(identity: string) {
  return { params: Promise.resolve({ identity }) };
}

describe("auth completion route", () => {
  test("returns a constrained same-origin notification page", async () => {
    const response = await GET(
      new Request("http://localhost/auth/complete/adfs"),
      context("adfs"),
    );
    const body = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("referrer-policy")).toBe("no-referrer");
    expect(response.headers.get("content-security-policy")).toContain(
      "default-src 'none'",
    );
    expect(body).toContain('identity: "adfs"');
    expect(body).toContain("window.location.origin");
  });

  test("rejects an unknown identity route", async () => {
    const response = await GET(
      new Request("http://localhost/auth/complete/other"),
      context("other"),
    );

    expect(response.status).toBe(400);
  });
});
