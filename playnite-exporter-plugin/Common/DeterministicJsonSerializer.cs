using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;

namespace PlayniteExporterPlugin.Common
{
    public static class DeterministicJsonSerializer
    {
        private static readonly JsonSerializerSettings Settings;

        static DeterministicJsonSerializer()
        {
            Settings = new JsonSerializerSettings
            {
                ContractResolver = new OrderedContractResolver(),
                Culture = CultureInfo.InvariantCulture,
                DateTimeZoneHandling = DateTimeZoneHandling.Utc,
                DateFormatHandling = DateFormatHandling.IsoDateFormat,
                DateFormatString = "yyyy-MM-ddTHH:mm:ss.fffZ",
                FloatFormatHandling = FloatFormatHandling.String,
                Formatting = Formatting.Indented,
                NullValueHandling = NullValueHandling.Include
            };
            Settings.Converters.Add(new OrderedDictionaryConverter());
        }

        public static string Serialize<T>(T value)
        {
            var sb = new StringBuilder();
            using var stringWriter = new StringWriter(sb, CultureInfo.InvariantCulture)
            {
                NewLine = "\n"
            };
            using var jsonWriter = new JsonTextWriter(stringWriter)
            {
                Formatting = Formatting.Indented,
                Indentation = 2,
                IndentChar = ' '
            };

            var serializer = JsonSerializer.Create(Settings);
            serializer.Serialize(jsonWriter, value);
            return sb.ToString();
        }

        public static T? Deserialize<T>(string json)
        {
            return JsonConvert.DeserializeObject<T>(json, Settings);
        }

        public class OrderedContractResolver : DefaultContractResolver
        {
            protected override IList<JsonProperty> CreateProperties(Type type, MemberSerialization memberSerialization)
            {
                var properties = base.CreateProperties(type, memberSerialization);
                return properties.OrderBy(p => p.PropertyName, StringComparer.Ordinal).ToList();
            }
        }

        public class OrderedDictionaryConverter : JsonConverter
        {
            public override bool CanConvert(Type objectType)
            {
                return typeof(IDictionary).IsAssignableFrom(objectType);
            }

            public override void WriteJson(JsonWriter writer, object? value, JsonSerializer serializer)
            {
                if (value == null)
                {
                    writer.WriteNull();
                    return;
                }

                var dictionary = (IDictionary)value;
                var keys = new List<string>();
                var keyLookup = new Dictionary<string, object?>();

                foreach (DictionaryEntry entry in dictionary)
                {
                    var keyStr = entry.Key?.ToString() ?? string.Empty;
                    keys.Add(keyStr);
                    keyLookup[keyStr] = entry.Value;
                }

                keys.Sort(StringComparer.Ordinal);

                writer.WriteStartObject();
                foreach (var key in keys)
                {
                    writer.WritePropertyName(key);
                    serializer.Serialize(writer, keyLookup[key]);
                }
                writer.WriteEndObject();
            }

            public override bool CanRead => false;

            public override object? ReadJson(JsonReader reader, Type objectType, object? existingValue, JsonSerializer serializer)
            {
                throw new NotSupportedException("OrderedDictionaryConverter is only intended for serialization.");
            }
        }
    }
}
