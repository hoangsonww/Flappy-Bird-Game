import type { NextFunction, Request, Response } from 'express';
import { ZodError, type ZodTypeAny, type z } from 'zod';
import { validationFailed } from '../utils/errors.js';

type Source = 'body' | 'query' | 'params';

interface Schemas {
  body?: ZodTypeAny;
  query?: ZodTypeAny;
  params?: ZodTypeAny;
}

function formatIssues(error: ZodError): Array<{ path: string; message: string; code: string }> {
  return error.issues.map((issue) => ({
    path: issue.path.join('.') || '(root)',
    message: issue.message,
    code: issue.code,
  }));
}

/**
 * Validate and coerce request parts with Zod.
 * On success the parsed value replaces the raw one, so handlers get typed input.
 */
export function validate(schemas: Schemas) {
  const sources = Object.keys(schemas) as Source[];

  return (req: Request, _res: Response, next: NextFunction): void => {
    for (const source of sources) {
      const schema = schemas[source];
      if (!schema) continue;
      const result = schema.safeParse(req[source]);
      if (!result.success) {
        next(
          validationFailed(`Invalid request ${source}`, {
            source,
            issues: formatIssues(result.error),
          }),
        );
        return;
      }
      // `query` and `params` are getters in Express 5; assign defensively.
      Object.defineProperty(req, source, {
        value: result.data,
        writable: true,
        configurable: true,
      });
    }
    next();
  };
}

export type Infer<T extends ZodTypeAny> = z.infer<T>;
