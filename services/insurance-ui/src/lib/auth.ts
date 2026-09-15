export const IDENTITIES = ["entra", "adfs"] as const;

export type Identity = (typeof IDENTITIES)[number];

export const IDENTITY_LABELS: Record<Identity, string> = {
  entra: "Entra ID",
  adfs: "ADFS",
};

export type AuthStatus = {
  identity: Identity;
  authenticated: true;
  attributePresent: boolean;
};

export type AuthStateChangedMessage = {
  type: "insurance-auth-state-changed";
  identity: Identity;
};

export function isIdentity(value: unknown): value is Identity {
  return typeof value === "string" && IDENTITIES.includes(value as Identity);
}

export function isAuthStatus(
  value: unknown,
  expectedIdentity?: Identity,
): value is AuthStatus {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const candidate = value as Partial<AuthStatus>;
  return (
    isIdentity(candidate.identity) &&
    (expectedIdentity === undefined || candidate.identity === expectedIdentity) &&
    candidate.authenticated === true &&
    typeof candidate.attributePresent === "boolean"
  );
}

export function isAuthStateChangedMessage(
  value: unknown,
): value is AuthStateChangedMessage {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const candidate = value as Partial<AuthStateChangedMessage>;
  return (
    candidate.type === "insurance-auth-state-changed" &&
    isIdentity(candidate.identity)
  );
}
