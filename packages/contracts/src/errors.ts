import type { ErrorCode } from './common.js';

/**
 * The Persian message and recommended client action for every error code.
 *
 * This lives in the contract rather than the client so that a code added server-side after a
 * release still renders correctly in apps already installed on students' devices.
 *
 * `action` tells the client what to *do*, not just what to say — DEVICE_LIMIT_REACHED should
 * open the device manager, not show a dead end.
 */
export type ClientAction =
  | 'none'
  | 'retry'
  | 'reauthenticate'
  | 'open_device_manager'
  | 'contact_support'
  | 'wait_and_retry';

export const ERROR_CATALOG: Record<
  ErrorCode,
  { http: number; messageFa: string; action: ClientAction }
> = {
  VALIDATION_FAILED: {
    http: 400,
    messageFa: 'اطلاعات ارسال‌شده معتبر نیست.',
    action: 'none',
  },
  UNAUTHENTICATED: {
    http: 401,
    messageFa: 'برای ادامه باید وارد حساب خود شوید.',
    action: 'reauthenticate',
  },
  TOKEN_EXPIRED: {
    http: 401,
    messageFa: 'نشست شما منقضی شده است.',
    action: 'reauthenticate',
  },
  FORBIDDEN: {
    http: 403,
    messageFa: 'شما به این بخش دسترسی ندارید.',
    action: 'none',
  },
  NOT_FOUND: {
    http: 404,
    messageFa: 'موردی یافت نشد.',
    action: 'none',
  },
  OTP_INVALID: {
    http: 400,
    messageFa: 'کد وارد شده صحیح نیست.',
    action: 'retry',
  },
  OTP_EXPIRED: {
    http: 400,
    messageFa: 'کد تأیید منقضی شده است. کد جدید دریافت کنید.',
    action: 'retry',
  },
  OTP_RATE_LIMITED: {
    http: 429,
    messageFa: 'تعداد درخواست‌ها زیاد است. کمی بعد تلاش کنید.',
    action: 'wait_and_retry',
  },
  DEVICE_LIMIT_REACHED: {
    http: 409,
    messageFa: 'به حداکثر تعداد دستگاه مجاز رسیده‌اید. یکی از دستگاه‌ها را حذف کنید.',
    action: 'open_device_manager',
  },
  DEVICE_REVOKED: {
    http: 403,
    messageFa: 'دسترسی این دستگاه لغو شده است.',
    action: 'reauthenticate',
  },
  DEVICE_UNKNOWN: {
    http: 400,
    messageFa: 'این دستگاه ثبت نشده است.',
    action: 'reauthenticate',
  },
  NOT_ENROLLED: {
    http: 403,
    messageFa: 'شما در این دوره ثبت‌نام نشده‌اید.',
    action: 'contact_support',
  },
  LICENSE_MISSING: {
    http: 403,
    messageFa: 'مجوز دسترسی برای این محتوا صادر نشده است.',
    action: 'contact_support',
  },
  LICENSE_EXPIRED: {
    http: 403,
    messageFa: 'اعتبار دسترسی شما به پایان رسیده است.',
    action: 'contact_support',
  },
  LICENSE_REVOKED: {
    http: 403,
    messageFa: 'مجوز دسترسی شما لغو شده است.',
    action: 'contact_support',
  },
  CONCURRENT_STREAM_LIMIT: {
    http: 409,
    messageFa: 'این محتوا در حال پخش روی دستگاه دیگری است.',
    action: 'none',
  },
  DOWNLOAD_NOT_ALLOWED: {
    http: 403,
    messageFa: 'دانلود برای این دوره فعال نیست.',
    action: 'none',
  },
  VIDEO_NOT_READY: {
    http: 409,
    messageFa: 'این ویدیو در حال پردازش است. کمی بعد بررسی کنید.',
    action: 'wait_and_retry',
  },
  CAPTURE_ENVIRONMENT_BLOCKED: {
    http: 403,
    messageFa: 'پخش در این محیط مجاز نیست. نرم‌افزار ضبط صفحه را ببندید.',
    action: 'none',
  },
  RATE_LIMITED: {
    http: 429,
    messageFa: 'تعداد درخواست‌ها زیاد است. کمی بعد تلاش کنید.',
    action: 'wait_and_retry',
  },
  INTERNAL: {
    http: 500,
    messageFa: 'خطای غیرمنتظره‌ای رخ داد. اگر تکرار شد با پشتیبانی تماس بگیرید.',
    action: 'contact_support',
  },
  CLASS_NOT_LIVE: {
    http: 409,
    messageFa: 'این کلاس هنوز شروع نشده است.',
    action: 'wait_and_retry',
  },
  CLASS_ENDED: {
    http: 410,
    messageFa: 'این کلاس به پایان رسیده است.',
    action: 'none',
  },
  CLASS_LOCKED: {
    http: 423,
    messageFa: 'میزبان ورود به کلاس را قفل کرده است.',
    action: 'wait_and_retry',
  },
  CLASS_FULL: {
    http: 409,
    messageFa: 'ظرفیت کلاس تکمیل است.',
    action: 'wait_and_retry',
  },
  CAPABILITY_MISSING: {
    http: 403,
    messageFa: 'در این کلاس اجازهٔ انجام این کار را ندارید.',
    action: 'none',
  },
  REMOVED_FROM_CLASS: {
    http: 403,
    messageFa: 'میزبان شما را از کلاس خارج کرده است.',
    action: 'none',
  },
  JOINED_ELSEWHERE: {
    http: 409,
    messageFa: 'با همین حساب از دستگاه دیگری وارد کلاس شده‌اید.',
    action: 'none',
  },
};
