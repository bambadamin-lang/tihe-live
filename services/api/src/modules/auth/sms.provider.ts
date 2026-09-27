import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { maskPhone } from '@tihe/contracts';

import type { Env } from '../../config/configuration.js';

export interface SmsProvider {
  sendOtp(phone: string, code: string): Promise<void>;
  /** True when the code is returned in the API response for local development. */
  readonly exposesCode: boolean;
}

/**
 * Development driver: prints the code to the API log instead of sending an SMS.
 *
 * Note what is logged — the masked number and the code. The code is harmless here because it is
 * only ever a local development code; the number is masked because the habit of masking it
 * everywhere is what stops an unmasked one appearing in a production log.
 */
@Injectable()
export class ConsoleSmsProvider implements SmsProvider {
  private readonly logger = new Logger('SMS');
  readonly exposesCode = true;

  async sendOtp(phone: string, code: string): Promise<void> {
    this.logger.log(`OTP for ${maskPhone(phone)}: ${code}`);
  }
}

/**
 * Kavenegar driver. Wired in M1 when a real API key exists.
 *
 * Kept as a distinct class rather than a branch inside one provider so the production path has no
 * chance of falling through to the console driver when a key is missing — it fails instead.
 */
@Injectable()
export class KavenegarSmsProvider implements SmsProvider {
  private readonly logger = new Logger('SMS');
  readonly exposesCode = false;

  constructor(private readonly config: ConfigService<Env, true>) {}

  async sendOtp(phone: string, _code: string): Promise<void> {
    const apiKey = this.config.get('SMS_API_KEY', { infer: true });
    if (!apiKey) {
      throw new Error('SMS_API_KEY is required when SMS_PROVIDER=kavenegar');
    }
    // M1: POST to Kavenegar's verify/lookup endpoint with a registered template.
    // Using the lookup API rather than plain send matters in Iran: plain SMS to a number that has
    // opted out of advertising messages is silently dropped, and OTP delivery would fail for a
    // subset of students with no error.
    this.logger.warn(
      `Kavenegar provider not yet implemented; OTP for ${maskPhone(phone)} not sent`,
    );
    throw new Error('Kavenegar SMS provider is not implemented yet (M1)');
  }
}

export const SMS_PROVIDER = Symbol('SMS_PROVIDER');
