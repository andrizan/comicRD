import type { ButtonHTMLAttributes } from "react";
import { cn } from "../../lib/utils";

type ButtonVariant = "default" | "ghost" | "outline" | "danger";

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant;
};

const buttonStyles: Record<ButtonVariant, string> = {
  default: "bg-app-accent text-white hover:brightness-110",
  ghost: "bg-transparent text-app-text hover:bg-app-surface",
  outline: "border border-app-border bg-app-surface text-app-text hover:bg-app-surface",
  danger: "bg-[#a73131] text-white hover:brightness-110",
};

export function Button({ className, variant = "default", ...props }: ButtonProps) {
  return (
    <button
      className={cn(
        "rounded-md px-3 py-2 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-60",
        buttonStyles[variant],
        className,
      )}
      {...props}
    />
  );
}
