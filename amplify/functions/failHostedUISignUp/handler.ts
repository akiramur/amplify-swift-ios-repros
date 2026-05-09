interface CognitoPreSignUpEvent {
  request: {
    userAttributes?: {
      email?: string;
    };
  };
}

export const handler = async (
  event: CognitoPreSignUpEvent,
): Promise<CognitoPreSignUpEvent> => {
  const email = event.request.userAttributes?.email?.toLowerCase() ?? "";

  if (email.startsWith("fail-hostedui")) {
    throw new Error(
      "Hosted UI repro: forced pre-sign-up rejection for this email pattern.",
    );
  }

  return event;
};
