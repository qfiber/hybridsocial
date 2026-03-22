// Proof-of-Work challenge solver
// Finds a nonce such that SHA-256(challenge + nonce) starts with `difficulty` zero bits

export interface PowChallenge {
  challenge: string;
  difficulty: number;
}

export interface PowSolution {
  challenge: string;
  nonce: number;
}

async function sha256(message: string): Promise<Uint8Array> {
  const encoder = new TextEncoder();
  const data = encoder.encode(message);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return new Uint8Array(hash);
}

function hasLeadingZeroBits(hash: Uint8Array, bits: number): boolean {
  const fullBytes = Math.floor(bits / 8);
  const remainingBits = bits % 8;

  for (let i = 0; i < fullBytes; i++) {
    if (hash[i] !== 0) return false;
  }

  if (remainingBits > 0) {
    const mask = 0xff << (8 - remainingBits);
    if ((hash[fullBytes] & mask) !== 0) return false;
  }

  return true;
}

export async function solvePow(challenge: PowChallenge): Promise<PowSolution> {
  let nonce = 0;
  const batchSize = 1000;

  while (true) {
    for (let i = 0; i < batchSize; i++) {
      const hash = await sha256(challenge.challenge + nonce);
      if (hasLeadingZeroBits(hash, challenge.difficulty)) {
        return { challenge: challenge.challenge, nonce };
      }
      nonce++;
    }
    // Yield to main thread between batches
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
}
