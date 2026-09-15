import { describe, expect, test } from "bun:test";
import { isAuthStateChangedMessage, isAuthStatus, isIdentity } from "./auth";

describe("isIdentity", () => {
  test("accepts only the two configured identity routes", () => {
    expect(isIdentity("entra")).toBe(true);
    expect(isIdentity("adfs")).toBe(true);
    expect(isIdentity("other")).toBe(false);
    expect(isIdentity(null)).toBe(false);
  });
});

describe("isAuthStatus", () => {
  test("accepts only the expected identity and complete schema", () => {
    expect(
      isAuthStatus(
        { identity: "entra", authenticated: true, attributePresent: false },
        "entra",
      ),
    ).toBe(true);
    expect(
      isAuthStatus(
        { identity: "adfs", authenticated: true, attributePresent: true },
        "entra",
      ),
    ).toBe(false);
    expect(
      isAuthStatus({ identity: "entra", authenticated: true }, "entra"),
    ).toBe(false);
  });
});

describe("isAuthStateChangedMessage", () => {
  test("accepts the notification schema", () => {
    expect(
      isAuthStateChangedMessage({
        type: "insurance-auth-state-changed",
        identity: "entra",
      }),
    ).toBe(true);
  });

  test("rejects unknown identities and message types", () => {
    expect(
      isAuthStateChangedMessage({
        type: "insurance-auth-state-changed",
        identity: "other",
      }),
    ).toBe(false);
    expect(
      isAuthStateChangedMessage({ type: "success", identity: "adfs" }),
    ).toBe(false);
  });
});
