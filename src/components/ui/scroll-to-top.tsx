import { ArrowUp } from "lucide-react";
import { useEffect, useState } from "react";

export function ScrollToTop() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const container = document.querySelector<HTMLElement>(".content-scroll");
    if (!container) return;
    const onScroll = () => setVisible(container.scrollTop > 400);
    container.addEventListener("scroll", onScroll, { passive: true });
    return () => container.removeEventListener("scroll", onScroll);
  }, []);

  if (!visible) return null;

  return (
    <button
      type="button"
      onClick={() => {
        document.querySelector<HTMLElement>(".content-scroll")?.scrollTo({
          top: 0,
          behavior: "smooth",
        });
      }}
      className="fixed bottom-6 right-6 z-30 flex h-10 w-10 items-center justify-center rounded-full border border-app-border bg-app-surface text-app-text shadow-lg transition hover:bg-app-surface"
      title="Scroll to top"
    >
      <ArrowUp size={18} />
    </button>
  );
}
