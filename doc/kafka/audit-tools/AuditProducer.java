import java.util.*;
import org.apache.kafka.clients.producer.*;
public class AuditProducer {
 public static void main(String[] a) throws Exception {
  Properties p=new Properties();
  p.put("bootstrap.servers","127.0.0.1:39092"); p.put("key.serializer","org.apache.kafka.common.serialization.ByteArraySerializer");
  p.put("value.serializer","org.apache.kafka.common.serialization.ByteArraySerializer"); p.put("compression.type","none");
  p.put("max.request.size","2097152");p.put("acks","all");
  byte[] data=new byte[Integer.parseInt(a[1])]; Arrays.fill(data,(byte)120);
  try(KafkaProducer<byte[],byte[]> producer=new KafkaProducer<>(p)) {
   RecordMetadata m=producer.send(new ProducerRecord<byte[],byte[]>(a[0],0,null,data)).get();
   System.out.println("bytes="+data.length+" offset="+m.offset());
  }
 }
}
