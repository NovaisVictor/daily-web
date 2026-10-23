/** The API's own message when it sent one, which says what to do next; the
 *  fallback only covers a body that is not the usual `{ error }`. */
export async function readErrorMessage(res: Response, fallback: string): Promise<string> {
  const data = await res.json().catch(() => ({}));
  return data.error ?? fallback;
}
