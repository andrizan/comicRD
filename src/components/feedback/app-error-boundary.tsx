import type { ReactNode } from "react";
import { Component } from "react";
import { AlertTriangle } from "lucide-react";

type Props = {
  children: ReactNode;
};

type State = {
  hasError: boolean;
};

export class AppErrorBoundary extends Component<Props, State> {
  state: State = {
    hasError: false,
  };

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error: unknown) {
    console.error("AppErrorBoundary caught error:", error);
  }

  private onReload = () => {
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex min-h-screen items-center justify-center bg-[#f8f3e7] p-6">
          <div className="w-full max-w-xl rounded-xl border border-[#d7a5a5] bg-[#fff5f5] p-6 text-center">
            <AlertTriangle className="mx-auto mb-3 text-[#a73131]" size={30} />
            <h2 className="text-xl font-bold">Terjadi Error di Aplikasi</h2>
            <p className="mt-2 text-sm text-[#7c3a3a]">
              Coba reload aplikasi. Jika masih terjadi, periksa log Tauri untuk detail error.
            </p>
            <button
              className="mt-4 rounded-md bg-[#a73131] px-4 py-2 text-sm font-semibold text-white"
              onClick={this.onReload}
              type="button"
            >
              Reload App
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
