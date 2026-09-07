/** Minimal element builder, so the views read as structure rather than as string concatenation. */

export type Child = Node | string | null | undefined | false;

export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Record<string, string> = {},
  ...children: Child[]
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) node.setAttribute(name, value);
  for (const child of children) {
    if (child === null || child === undefined || child === false) continue;
    node.append(typeof child === "string" ? document.createTextNode(child) : child);
  }
  return node;
}

/** Appends children, dropping the absent ones a conditional section leaves behind. */
export function append(node: HTMLElement, ...children: Child[]): void {
  for (const child of children) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child);
  }
}

export function clear(node: HTMLElement): void {
  while (node.firstChild !== null) node.firstChild.remove();
}

/** Links a repository path relative to `dist/index.html`, where the site is built. */
export function repoLink(path: string): HTMLAnchorElement {
  return el("a", { href: `../../${path}`, class: "path" }, path);
}
