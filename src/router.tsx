import { createRootRoute, createRoute, createRouter } from "@tanstack/react-router";
import { ComicPage } from "./routes/ComicPage";
import { Layout } from "./routes/Layout";
import { LibraryPage } from "./routes/LibraryPage";
import { ReaderPage } from "./routes/ReaderPage";

const rootRoute = createRootRoute({
  component: Layout,
});

const libraryRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/",
  component: LibraryPage,
});

const comicRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/comic/$comicId",
  component: ComicPage,
});

const readerRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/reader/$chapterId",
  component: ReaderPage,
});

const routeTree = rootRoute.addChildren([libraryRoute, comicRoute, readerRoute]);

export const router = createRouter({ routeTree });

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
