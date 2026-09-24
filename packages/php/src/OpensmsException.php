<?php

declare(strict_types=1);

namespace Opensms;

use Exception;
use ReflectionProperty;
use Throwable;

/**
 * Thrown for every non-2xx API response, for a transport failure that
 * survives all retries (status 0), and by webhook verification
 * (status 0, code "invalid_signature" or "expired_signature").
 *
 * Mapped from the RFC 9457 problem+json body the API returns. Most OpenSMS
 * errors carry no `code`, so branch on {@see getStatus()} first and use
 * {@see getDetail()} for display. Note that insufficient scope is 401 on
 * messages and otp but 403 everywhere else.
 *
 * The inherited {@see Exception::getCode()} is final, so the API's string
 * error code is stored in the inherited `code` slot (as the Axene SDK does)
 * and is also available, typed, from {@see getErrorCode()}.
 */
final class OpensmsException extends Exception
{
    /**
     * @param array<string, list<string>>|null $errors
     */
    public function __construct(
        private readonly int $status,
        string $message,
        private readonly ?string $type = null,
        private readonly ?string $title = null,
        private readonly ?string $detail = null,
        private readonly ?string $errorCode = null,
        private readonly ?string $traceId = null,
        private readonly ?array $errors = null,
        private readonly ?string $requestId = null,
        private readonly ?float $retryAfter = null,
        private readonly mixed $body = null,
        ?Throwable $previous = null,
    ) {
        parent::__construct($message, 0, $previous);

        if ($errorCode !== null) {
            $prop = new ReflectionProperty(Exception::class, 'code');
            $prop->setValue($this, $errorCode);
        }
    }

    /** HTTP status. 0 means no response (network failure, timeout, bad signature). */
    public function getStatus(): int
    {
        return $this->status;
    }

    /** Problem `type`: usually "about:blank", else https://api.opensms.io/problems/<code>. */
    public function getType(): ?string
    {
        return $this->type;
    }

    /** Problem `title`, for example "Bad Request". */
    public function getTitle(): ?string
    {
        return $this->title;
    }

    /** Problem `detail`: the human-readable explanation. */
    public function getDetail(): ?string
    {
        return $this->detail;
    }

    /** Problem `code`, when the handler sets one (most do not). */
    public function getErrorCode(): ?string
    {
        return $this->errorCode;
    }

    /** Problem `trace_id`, when present. */
    public function getTraceId(): ?string
    {
        return $this->traceId;
    }

    /**
     * Problem `errors`: field name to messages, when present.
     *
     * @return array<string, list<string>>|null
     */
    public function getErrors(): ?array
    {
        return $this->errors;
    }

    /** `X-Request-ID` header (message and OTP admission rejections). */
    public function getRequestId(): ?string
    {
        return $this->requestId;
    }

    /** `Retry-After` header in seconds (429 and some 503), when present. */
    public function getRetryAfter(): ?float
    {
        return $this->retryAfter;
    }

    /** The raw decoded body (array), or the raw text when it was not JSON. */
    public function getBody(): mixed
    {
        return $this->body;
    }
}
