export class AppError extends Error {
  constructor(category, status, message, retryable = false) {
    super(message);
    this.name = "AppError";
    this.category = category;
    this.status = status;
    this.retryable = retryable;
  }
}

export function errorBody(error) {
  const safe = error instanceof AppError
    ? error
    : new AppError("internal_error", 500, "The backend could not complete the request", true);
  return {
    error: {
      category: safe.category,
      message: safe.message,
      retryable: safe.retryable,
    },
  };
}
