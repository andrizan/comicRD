import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...values: ClassValue[]) {
  return twMerge(clsx(values));
}

export function unixToLocale(value: number) {
  if (!value) return "-";
  return new Date(value * 1000).toLocaleString();
}
