# Separate Xbox sign-in from stream access

XFrame currently treats a successful xCloud authorization check as the condition for being signed in. We will keep Xbox Sign-in independent of Cloud Gaming Access and Console Access, because a user may be entitled to stream from an associated console without access to an xCloud offering. This requires separate capability states and errors in the account/library UI rather than one global access gate.
