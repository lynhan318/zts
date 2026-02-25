function count(n: number): number {
  console.log("Current n: " + n);
  if (n < 5) {
    count(n + 1);
  }
  console.log("Return n: " + n);
  return n;
}
const n = count(0);
console.log("Last n", n);
