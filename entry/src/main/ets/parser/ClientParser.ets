const CLIENT_MAP: Record<string, string> = {
  '1': 'iOS',
  '7': 'iOS',
  '8': 'Android',
  '9': 'Windows Phone',
  '31': 'Android',
  '100': 'Android',
  '101': 'iOS',
  '103': 'Windows Phone',
};

export function parseFromClient(code: string | number | undefined): string {
  if (!code) return '';
  const raw: string = String(code).trim();
  if (!raw || raw === '0' || raw === '0 /') return '';
  const parts: string[] = raw.split('/');
  const codePart: string = parts[0].trim();
  const modelPart: string = parts.length > 1 ? parts[1].trim() : '';
  const mapped: string = CLIENT_MAP[codePart] ?? '';
  if (modelPart.length > 0) {
    return mapped.length > 0 ? `${mapped} ${modelPart}` : modelPart;
  }
  return mapped;
}
