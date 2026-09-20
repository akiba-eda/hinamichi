import { route } from "../http.js";
export default route({ methods: ["GET"], auth: "none" }, async () => ({ ok: true, service: "hinamichi", time: new Date().toISOString() }));
