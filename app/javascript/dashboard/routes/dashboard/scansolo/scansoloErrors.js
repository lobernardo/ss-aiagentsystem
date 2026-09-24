// UI-05 / UI-09: the message a ScanSolo toast shows for a failed request —
// the server's own message when it sent one, otherwise the caller fallback.
export const serverErrorMessage = (error, fallback) => {
  const data = error?.response?.data;
  if (data?.message) return data.message;
  if (Array.isArray(data?.details) && data.details.length) {
    return data.details.join(', ');
  }
  if (Array.isArray(data?.errors) && data.errors.length) {
    return data.errors.join(', ');
  }
  return data?.error || fallback;
};
